#!/usr/bin/env python3
"""cc-account.py — Claude Code が「今どのアカウント/設定置き場/プロバイダを使っているか」を判定する。

使い方:
    python3 claude/scripts/cc-account.py          # 人間可読な1行を出す
    python3 claude/scripts/cc-account.py --json    # JSON を stdout に出す
    python3 claude/scripts/cc-account.py --no-file # ファイル読み取りを省き、環境変数だけで推測する

背景（この dotfiles の実態。詳細は claude/AGENTS.md の
「プロジェクト別 Claude アカウント切り替え」参照）:
  - 既定（個人 = yuhgo アカウント）: CLAUDE_CONFIG_DIR は未設定。設定は ~/.claude/ だが、
    アカウント情報は ~/.claude.json（ホーム直下、~/.claude/ の中ではない）
  - 会社（adixi）: innocom-data-connect-garage 配下で direnv が
    CLAUDE_CONFIG_DIR=$HOME/.claude-adixi を export する。この場合アカウント情報は
    $CLAUDE_CONFIG_DIR/.claude.json（= ~/.claude-adixi/.claude.json）
    → 個人は ~/.claude.json、会社は $CLAUDE_CONFIG_DIR/.claude.json という非対称なパスを吸収する。
  - 組織名は JSON の oauthAccount.organizationName から読む。
    個人アカウントの組織名は "<メールアドレス>'s Organization" という形になる。
    会社側の組織名は環境変数 CC_ACCOUNT_ORG_NAME で指定する（既定は下の DEFAULT_ORG_NAME）。
  - Bedrock: CLAUDE_CODE_USE_BEDROCK=1（+ 任意で AWS_REGION / AWS_PROFILE / ANTHROPIC_MODEL）。
    Bedrock は「場所に依存しない」＝ CLAUDE_CONFIG_DIR とは独立の軸。

セキュリティ注意:
  - アカウントの中身（トークン等）は読まない・出力しない。
    .claude.json から読むのは oauthAccount.organizationName フィールドのみ。
  - .claude.json が存在しない/壊れた JSON/権限エラーでも例外を投げず、
    account="unknown" として exit 0 で返す。
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Optional


def _truthy(value: Optional[str]) -> bool:
    """環境変数の値が truthy かどうかを判定する（"1" / "true" / "yes" 系を許容）。"""
    if value is None:
        return False
    return value.strip().lower() in ("1", "true", "yes", "on")


def get_home_dir() -> Path:
    """HOME を返す（テスト時に環境変数で差し替え可能にするための切り出し）。"""
    home = os.environ.get("HOME")
    if home:
        return Path(home)
    return Path.home()


def get_config_dir_info(home: Optional[Path] = None) -> dict:
    """CLAUDE_CONFIG_DIR の有無から config_dir と source を決める。

    戻り値: {"config_dir": <絶対パス文字列>, "source": "env" | "default"}
    """
    if home is None:
        home = get_home_dir()

    env_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if env_dir is not None and env_dir.strip():
        return {"config_dir": str(Path(env_dir.strip()).expanduser()), "source": "env"}
    if env_dir is not None:
        # 空文字が入っているのは direnv / .envrc 側の設定ミス。既定に落として黙るのではなく、
        # source=invalid として呼び出し側が気づけるようにする。
        return {"config_dir": str(home / ".claude"), "source": "invalid"}
    return {"config_dir": str(home / ".claude"), "source": "default"}


def get_claude_json_path(config_dir_info: dict, home: Optional[Path] = None) -> Path:
    """アカウント情報 (.claude.json) の実パスを返す。

    個人（source=default）は ~/.claude.json（~/.claude/ の外）。
    会社等（source=env）は $CLAUDE_CONFIG_DIR/.claude.json。
    この非対称性が本スクリプトの核心の吸収対象。
    """
    if home is None:
        home = get_home_dir()

    if config_dir_info["source"] == "env":
        return Path(config_dir_info["config_dir"]) / ".claude.json"
    return home / ".claude.json"


def read_organization_name(claude_json_path: Path) -> Optional[str]:
    """.claude.json から oauthAccount.organizationName だけを安全に読む。

    ファイル不在・壊れた JSON・権限エラーなど、どんな理由でも例外を投げず None を返す。
    他のフィールド（トークン等）は一切読み取らない。
    """
    try:
        with open(claude_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None

    if not isinstance(data, dict):
        return None

    oauth_account = data.get("oauthAccount")
    if not isinstance(oauth_account, dict):
        return None

    org_name = oauth_account.get("organizationName")
    if isinstance(org_name, str) and org_name:
        return org_name
    return None


# 会社アカウントの組織名と、それを指す短縮名。
# 別の組織で使うときは環境変数で上書きする（コードを触らなくてよい）:
#   export CC_ACCOUNT_ORG_NAME="Example Inc."
#   export CC_ACCOUNT_ORG_LABEL="example"
DEFAULT_ORG_NAME = "ADiXi Inc."
DEFAULT_ORG_LABEL = "adixi"


def get_work_org() -> tuple[str, str]:
    """会社組織の (組織名, 短縮名) を返す。環境変数で上書きできる。"""
    name = os.environ.get("CC_ACCOUNT_ORG_NAME", "").strip() or DEFAULT_ORG_NAME
    label = os.environ.get("CC_ACCOUNT_ORG_LABEL", "").strip() or DEFAULT_ORG_LABEL
    return name, label


def classify_account(organization_name: Optional[str]) -> str:
    """組織名から短縮アカウント名を判定する。

    - 会社の組織名（既定 "ADiXi Inc."、CC_ACCOUNT_ORG_NAME で上書き可） → その短縮名
    - "...'s Organization"（個人の既定組織名パターン） → personal
    - それ以外/不明 → unknown
    """
    if not organization_name:
        return "unknown"

    work_name, work_label = get_work_org()
    name = organization_name.strip()
    if name.lower() == work_name.lower():
        return work_label
    if name.endswith("'s Organization"):
        return "personal"
    return "unknown"


def classify_account_from_config_dir(config_dir: str, source: str) -> str:
    """--no-file 用: config_dir のパスだけからアカウントを推測する。

    .claude-adixi を含めば adixi、CLAUDE_CONFIG_DIR 未設定（既定 ~/.claude）なら personal。
    """
    if ".claude-adixi" in config_dir:
        return "adixi"
    if source == "env":
        # 既知パターン以外の config_dir が明示されている場合は personal と断定しない
        # （会社側のディレクトリ名を変えたときに黙って誤表示しないため）。
        return "unknown"
    return "personal"


def get_provider_info() -> dict:
    """provider（bedrock/anthropic）と、bedrock 時の付随情報を返す。"""
    info: dict = {}
    if _truthy(os.environ.get("CLAUDE_CODE_USE_BEDROCK")):
        info["provider"] = "bedrock"
        aws_region = os.environ.get("AWS_REGION")
        if aws_region:
            info["aws_region"] = aws_region
        model = os.environ.get("ANTHROPIC_MODEL")
        if model:
            info["model"] = model
    else:
        info["provider"] = "anthropic"
    return info


def resolve(no_file: bool = False, home: Optional[Path] = None) -> dict:
    """判定本体。例外を投げない契約を守るため、内部で個別に try/except する。"""
    if home is None:
        home = get_home_dir()

    config_dir_info = get_config_dir_info(home=home)
    result: dict = {
        "config_dir": config_dir_info["config_dir"],
        "source": config_dir_info["source"],
    }

    if no_file:
        result["account"] = classify_account_from_config_dir(
            config_dir_info["config_dir"], config_dir_info["source"]
        )
    else:
        claude_json_path = get_claude_json_path(config_dir_info, home=home)
        org_name = read_organization_name(claude_json_path)
        result["account"] = classify_account(org_name)
        if org_name:
            result["organization_name"] = org_name

    result.update(get_provider_info())
    return result


def format_human_readable(result: dict) -> str:
    parts = [
        f"account={result.get('account', 'unknown')}",
        f"provider={result.get('provider', 'anthropic')}",
        f"config_dir={result.get('config_dir', '')}",
        f"source={result.get('source', 'default')}",
    ]
    return " ".join(parts)


def main() -> int:
    args = sys.argv[1:]
    as_json = "--json" in args
    no_file = "--no-file" in args

    try:
        result = resolve(no_file=no_file)
    except Exception:
        # 契約: どんな理由でも例外を投げず unknown を返す
        result = {
            "account": "unknown",
            "config_dir": str(get_home_dir() / ".claude"),
            "source": "default",
            "provider": "anthropic",
        }

    if as_json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(format_human_readable(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
