# cc-account

Claude Code の**アカウント / 設定置き場 / プロバイダ**を確認・切り替えする zsh プラグイン。

`direnv` による自動切り替えは「場所で決まる」ため、**今どっちなのかが見えない**・
**その場だけ別アカウントで試せない**という不満が残る。それを埋めるのがこれ。

```console
$ cc-account
account=personal provider=anthropic config_dir=/Users/you/.claude source=default

$ cc-account use adixi
設定置き場を会社 (adixi) に切り替えました（このシェル限り。cd で direnv に戻ります）
```

## 構成

| 部品 | 形 | 役割 |
|------|---|------|
| `bin/cc-account.py` | Python | 環境変数と設定ファイルから現在状態を判定し JSON で返す |
| `cc-account.plugin.zsh` | zsh 関数 | `export` / `unset` を呼び出し元のシェルに残す |
| `statusline/account-state.ts` | TS モジュール | 現在の状態を**素の値**で返す（表示は呼び出し側の裁量） |

判定を切り出しているのは、**シェル関数と statusline が同じ答えを見る**ため。
切り替えが zsh 関数なのは、独立 CLI（子プロセス）では `export` が親シェルに残らず
**原理的に不可能**だから。

## インストール

```sh
ghq get yuhgo/cc-account          # または git clone
```

`.zshrc` に 1 行:

```sh
source ~/ghq/github.com/yuhgo/cc-account/cc-account.plugin.zsh
```

プラグインは**自分の置き場所を自動で解決する**ので、どこに clone してもよい。

### statusline に出す（任意）

**このモジュールは表示を持たない**。絵文字・ラベル・色・行の組み立ては
呼び出し側の裁量とし、こちらは素の値だけを返す。

```ts
import { getAccountState } from "<clone先>/statusline/account-state.ts";

const { account, provider, source } = getAccountState();
const label = provider === "bedrock" ? `☁️ ${provider}` : `👤 ${account}`;
```

| キー | 値 |
|------|---|
| `account` | `personal` / `adixi` / 組織名を上書きしたときはその短縮名 |
| `provider` | `anthropic` / `bedrock` |
| `configDir` | 実際に使われている設定ディレクトリ |
| `source` | `default` / `env` / `invalid`（`CLAUDE_CONFIG_DIR` が空文字） |

`account` と `provider` は**独立の軸**なので、両方そのまま返す。
どちらを優先して出すか（例: Bedrock 時はプロバイダだけ出す）は呼び出し側が決める。

判定は**環境変数のみ**で行い、子プロセスもファイル読み取りも挟まない
（`cc-account.py --no-file` と同じロジック）。描画のたびに走るため。

## 使い方

```sh
cc-account               # 現在の状態を表示
cc-account use personal  # 設定置き場を個人に戻す（= CLAUDE_CONFIG_DIR を unset）
cc-account use adixi     # 設定置き場を会社に上書き（このシェル限り）
cc-account use bedrock   # Bedrock を有効化（場所非依存）
cc-account off           # Bedrock のみ解除
```

- **`use personal` は `export` ではなく `unset`**。個人は「`CLAUDE_CONFIG_DIR` 未設定」が正なので、
  ここで明示 export すると direnv より優先され、会社 dir へ `cd` しても個人に固定されてしまう
- **`use adixi` / `use personal` はその場のシェル限り**。`cd` すれば direnv が再判定して元に戻る
- **`off` は Bedrock のみを解除する**。設定置き場（`CLAUDE_CONFIG_DIR`）には触らない。
  置き場は direnv の管轄であり、`off` がそこまで面倒を見ると
  「direnv と手動のどちらが勝つのか」が曖昧になるため、責務を分けている

### 判定スクリプト単体

```console
$ python3 bin/cc-account.py --json
{"config_dir": "/Users/you/.claude", "source": "default", "account": "personal", "provider": "anthropic"}

$ python3 bin/cc-account.py --no-file --json   # ファイルを読まず環境変数だけで推測
```

| キー | 意味 |
|------|------|
| `account` | `personal` / `adixi` / `unknown` |
| `config_dir` | 実際に使われている設定ディレクトリ |
| `provider` | `anthropic` / `bedrock` |
| `source` | `default`（未設定）/ `env`（`CLAUDE_CONFIG_DIR` あり）/ `invalid`（空文字） |

## 設定

| 環境変数 | 既定 | 用途 |
|---------|------|------|
| `CC_ACCOUNT_ADIXI_DIR` | `$HOME/.claude-adixi` | `use adixi` の切り替え先 |
| `CC_ACCOUNT_ORG_NAME` | `ADiXi Inc.` | 会社アカウントの組織名（`.claude.json` の `organizationName` と突き合わせる） |
| `CC_ACCOUNT_ORG_LABEL` | `adixi` | 上記に対応する短縮名（表示に使う） |

別の組織で使うなら `.zshrc` で上書きする:

```sh
export CC_ACCOUNT_ORG_NAME="Example Inc."
export CC_ACCOUNT_ORG_LABEL="example"
export CC_ACCOUNT_ADIXI_DIR="$HOME/.claude-example"
```

## Bedrock が「場所非依存」である理由

`direnv` の `.envrc` が export するのは **`CLAUDE_CONFIG_DIR` のみ**。
Bedrock 系（`CLAUDE_CODE_USE_BEDROCK` ほか）は direnv に触られないので、`cd` をまたいでも残る。
つまり「設定置き場（場所で決まる）」と「プロバイダ（場所に依存しない）」は**独立した 2 軸**であり、
追加のガードなしにこの性質が成り立つ。

> `/setup-bedrock` ウィザードは `$CLAUDE_CONFIG_DIR/settings.json` に書くため、
> **direnv で config dir が切り替わると設定が付いてこない**。
> `cc-account` が環境変数方式を採っているのはこのため。

## テスト

```sh
bash tests/run-cc-account-tests.sh      # 判定スクリプト（13 ケース）
bun test tests/account-state.test.ts    # 状態モジュール（9 ケース）
```

fixture は一時ディレクトリに作り、`HOME` / `CLAUDE_CONFIG_DIR` を差し替えるので
**実ユーザーの設定は読まないし壊さない**。

## Gotchas

- **`.claude.json` の場所は個人と会社で非対称**。個人は `~/.claude.json`（`~/.claude/` の外）、
  会社は `$CLAUDE_CONFIG_DIR/.claude.json`。`cc-account.py` はこれを吸収している
- **判定に使うのは `oauthAccount.organizationName` だけ**。`.claude.json` にはトークンが
  含まれうるので、それ以外のフィールドは読まないし出力にも混ぜない
- **組織名は完全一致で突き合わせている**（大文字小文字は無視）。組織名が変わったら
  `CC_ACCOUNT_ORG_NAME` を更新する。未知の名前は `unknown` に落ちる
- **`ANTHROPIC_API_KEY` が設定されていると、そちらが優先されてサブスクは使われない**。
  切り替えが効かないときはまずこの環境変数を疑う
- **WSL 未確認**。macOS でのみ動作確認済み

## ライセンス

MIT
