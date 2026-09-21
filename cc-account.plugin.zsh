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
      echo "Bedrock を解除しました（設定置き場は direnv の判定に従います）"
      ;;

    -h|--help|help)
      echo "使い方:"
      echo "  cc-account               現在の状態を表示"
      echo "  cc-account use personal  設定置き場を個人に戻す"
      echo "  cc-account use adixi     設定置き場を会社に上書き（このシェル限り）"
      echo "  cc-account use bedrock   Bedrock を有効化（場所非依存）"
      echo "  cc-account off           Bedrock のみ解除"
      ;;

    *)
      echo "cc-account: 不明なサブコマンド: $1" >&2
      echo "使い方: cc-account [use {personal|adixi|bedrock} | off | --help]" >&2
      return 1
      ;;
  esac
}
