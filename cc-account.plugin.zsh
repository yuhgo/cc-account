# cc-account — Claude Code のアカウント / プロバイダを確認・切り替えする。
#
# 判定は bin/cc-account.py に委譲し、statusline と同じ答えを見る。
#
#   cc-account              現在の状態を表示
#   cc-account use personal 設定置き場を個人に戻す（= CLAUDE_CONFIG_DIR を unset）
#   cc-account use adixi    設定置き場を会社に上書き（このシェル限り）
#   cc-account use bedrock  Bedrock を有効化（場所非依存。cd しても外れない）
#   cc-account off          Bedrock のみ解除（設定置き場は direnv に委ねる）
#
# 独立 CLI ではなく関数なのは、export を呼び出し元のシェルに残す必要があるため
# （子プロセスの export は親に伝わらない）。
#
# 使い方（.zshrc に 1 行）:
#   source /path/to/cc-account/cc-account.plugin.zsh

# このファイル自身の場所を基準に判定スクリプトを解決する。
# ${(%):-%N} は source 中のファイル名を返す zsh のイディオム。
typeset -g _CC_ACCOUNT_ROOT="${${(%):-%N}:A:h}"

# 会社（adixi）用の設定置き場。環境に合わせて上書きできる。
: "${CC_ACCOUNT_ADIXI_DIR:=$HOME/.claude-adixi}"

# 会社アカウントの短縮名。判定は bin/cc-account.py が持つが、help の文面でも
# 参照するので既定値をこちらにも置く（両者の既定は一致させる）。
: "${CC_ACCOUNT_ORG_LABEL:=adixi}"

# Bedrock の素材 → Claude Code が実際に読む変数名 への対応表。
#
# 素材（CC_ACCOUNT_BEDROCK_*）は ~/.zshrc.local などの追跡外ファイルに置く。
# 右辺を直接 export してはいけない: ANTHROPIC_DEFAULT_* の値は us.anthropic.*
# 形式の Bedrock 専用 ID なので、Bedrock 無効時に効くとサブスク経由のモデル解決が
# 壊れる。AWS_REGION も AWS CLI 全体の既定リージョンを書き換えてしまう。
# そのため「Bedrock を有効化している間だけ」立てる。
typeset -gA _CC_ACCOUNT_BEDROCK_VARS=(
  CC_ACCOUNT_BEDROCK_REGION       AWS_REGION
  CC_ACCOUNT_BEDROCK_API_KEY      AWS_BEARER_TOKEN_BEDROCK
  CC_ACCOUNT_BEDROCK_MODEL_OPUS   ANTHROPIC_DEFAULT_OPUS_MODEL
  CC_ACCOUNT_BEDROCK_MODEL_SONNET ANTHROPIC_DEFAULT_SONNET_MODEL
  CC_ACCOUNT_BEDROCK_MODEL_HAIKU  ANTHROPIC_DEFAULT_HAIKU_MODEL
)

# 連想配列はキー順を保証しないので、表示用の並びを別に持つ
# （設定する順序＝リージョン → 認証 → モデルで読めるようにする）。
typeset -ga _CC_ACCOUNT_BEDROCK_ORDER=(
  CC_ACCOUNT_BEDROCK_REGION
  CC_ACCOUNT_BEDROCK_API_KEY
  CC_ACCOUNT_BEDROCK_MODEL_OPUS
  CC_ACCOUNT_BEDROCK_MODEL_SONNET
  CC_ACCOUNT_BEDROCK_MODEL_HAIKU
)

function cc-account() {
  local script="$_CC_ACCOUNT_ROOT/bin/cc-account.py"

  case "${1:-}" in
    "")
      if [[ ! -f "$script" ]]; then
        echo "cc-account: 判定スクリプトが見つかりません: $script" >&2
        return 1
      fi
      python3 "$script"
      ;;

    use)
      case "${2:-}" in
        personal)
          # 個人は「CLAUDE_CONFIG_DIR 未設定」が正（既定 = ~/.claude）。
          # ここで明示 export すると direnv より優先され、会社 dir へ cd しても
          # 個人に固定されてしまうため、export ではなく unset する。
          unset CLAUDE_CONFIG_DIR
          echo "設定置き場を個人に戻しました（cd 先で direnv が再判定します）"
          ;;
        adixi)
          export CLAUDE_CONFIG_DIR="$CC_ACCOUNT_ADIXI_DIR"
          echo "設定置き場を会社 (adixi) に切り替えました（このシェル限り。cd で direnv に戻ります）"
          ;;
        bedrock)
          export CLAUDE_CODE_USE_BEDROCK=1

          # 素材が定義されているものだけを本来の変数名へ展開する。
          local src dst
          for src dst in ${(kv)_CC_ACCOUNT_BEDROCK_VARS}; do
            [[ -n "${(P)src}" ]] && export "$dst=${(P)src}"
          done

          if [[ -z "$CC_ACCOUNT_BEDROCK_API_KEY" && -z "$AWS_BEARER_TOKEN_BEDROCK" ]]; then
            echo "cc-account: 警告 — 認証情報が見つかりません" >&2
            echo "  CC_ACCOUNT_BEDROCK_API_KEY を ~/.zshrc.local に設定してください" >&2
            echo "  （IAM ロール / AWS プロファイル経由で認証している場合はこの警告を無視して構いません）" >&2
          fi

          echo "Bedrock を有効化しました（場所非依存。解除は 'cc-account off'）"
          ;;
        *)
          echo "cc-account: 不明な切り替え先: ${2:-（未指定）}" >&2
          echo "使い方: cc-account use {personal|adixi|bedrock}" >&2
          return 1
          ;;
      esac
      ;;

    off)
      # Bedrock のみ解除する。CLAUDE_CONFIG_DIR は direnv の管轄なので触らない。
      unset CLAUDE_CODE_USE_BEDROCK

      # use bedrock が展開した変数だけを戻す。素材が無いものは触らない
      # （AWS_PROFILE 運用で元から AWS_REGION を持っている環境を壊さないため）。
      local src dst
      for src dst in ${(kv)_CC_ACCOUNT_BEDROCK_VARS}; do
        [[ -n "${(P)src}" ]] && unset "$dst"
      done

      echo "Bedrock を解除しました（設定置き場は direnv の判定に従います）"
      ;;

    -h|--help|help)
      echo "cc-account — Claude Code のアカウント / プロバイダを確認・切り替える"

      # 現在の状態も出す。「何が効いているか」が分からないまま
      # 切り替えコマンドを選ばせないため。
      if [[ -f "$script" ]]; then
        echo ""
        echo "現在"
        python3 "$script" 2>/dev/null | sed 's/^/  /'
      fi

      echo ""
      echo "表示"
      echo "  cc-account            現在の状態を表示"
      echo ""
      echo "切り替え（いずれも実行したシェル限り。別のタブには及ばない）"
      echo "  use personal   設定置き場を個人に戻す（CLAUDE_CONFIG_DIR を unset）"
      # サブコマンド名は adixi 固定。ラベルだけが CC_ACCOUNT_ORG_LABEL で変わるので、
      # 既定（adixi）から変えている環境では括弧で実体を補う。
      if [[ "$CC_ACCOUNT_ORG_LABEL" == "adixi" ]]; then
        echo "  use adixi      設定置き場を会社に上書き"
      else
        echo "  use adixi      設定置き場を会社（$CC_ACCOUNT_ORG_LABEL）に上書き"
      fi
      echo "                 → cd すると direnv の判定に戻る"
      echo "  use bedrock    Bedrock を有効化（場所非依存。cd しても外れない）"
      echo "  off            Bedrock のみ解除（設定置き場は direnv に委ねる）"
      echo ""
      echo "Bedrock の素材（~/.zshrc.local に置く。git 追跡外・権限 600）"

      local src pad missing=0
      for src in $_CC_ACCOUNT_BEDROCK_ORDER; do
        pad="${(r:34:: :)src}"
        if [[ -n "${(P)src}" ]]; then
          echo "  $pad ✓"
        else
          echo "  $pad -"
          (( missing++ ))
        fi
      done
      if (( missing > 0 )); then
        echo "  未設定（-）のものは use bedrock でも展開されません。"
      fi

      echo ""
      echo "詳細: https://github.com/yuhgo/cc-account"
      ;;

    *)
      echo "cc-account: 不明なサブコマンド: $1" >&2
      echo "使い方: cc-account [use {personal|adixi|bedrock} | off | --help]" >&2
      return 1
      ;;
  esac
}
