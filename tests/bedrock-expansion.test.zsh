#!/usr/bin/env zsh
# cc-account use bedrock / off が素材変数（CC_ACCOUNT_BEDROCK_*）を
# 本来の変数名へ展開し、off で正しく戻すことを検証する。
#
# 値そのものは一切出力しない（set / unset のみを比較する）。
#
#   zsh tests/bedrock-expansion.test.zsh

set -u
emulate -L zsh

typeset -g root="${${(%):-%N}:A:h:h}"
source "$root/cc-account.plugin.zsh"

typeset -g fails=0

# 期待する状態を「set / unset の並び」で突き合わせる。
check() {
  local label="$1"; shift
  local -a expected=("$@")
  local -a targets=(
    CLAUDE_CODE_USE_BEDROCK
    AWS_REGION
    AWS_BEARER_TOKEN_BEDROCK
    ANTHROPIC_DEFAULT_OPUS_MODEL
    ANTHROPIC_DEFAULT_SONNET_MODEL
  )
  local -a actual=()
  local v
  for v in $targets; do
    [[ -n "${(P)v:-}" ]] && actual+=(set) || actual+=(unset)
  done
  if [[ "${actual[*]}" == "${expected[*]}" ]]; then
    print "OK   [$label]"
  else
    print "NG   [$label]"
    print "     期待: ${expected[*]}"
    print "     実際: ${actual[*]}"
    (( fails++ ))
  fi
}

# --- 素材を 3 件だけ用意する（SONNET は意図的に未設定にする）---
# 値は「空でないこと」しか見ないので、すべて同じプレースホルダで足りる。
# 本物らしい文字列を置くとシークレットスキャナが誤検知するため意図的に避ける。
typeset -g PLACEHOLDER="PLACEHOLDER"
typeset -ga present=(
  CC_ACCOUNT_BEDROCK_REGION
  CC_ACCOUNT_BEDROCK_API_KEY
  CC_ACCOUNT_BEDROCK_MODEL_OPUS
)
for v in $present; do export "$v=$PLACEHOLDER"; done
unset CC_ACCOUNT_BEDROCK_MODEL_SONNET CC_ACCOUNT_BEDROCK_MODEL_HAIKU 2>/dev/null

check "初期状態は全て unset" unset unset unset unset unset

cc-account use bedrock >/dev/null 2>&1
# 素材のある 3 件は立ち、素材の無い SONNET は立たない
check "use bedrock で素材のあるものだけ展開" set set set set unset

cc-account off >/dev/null
check "off で展開したものだけ戻る" unset unset unset unset unset

# --- 素材が無い変数を off が消さないこと（AWS_PROFILE 運用の保護）---
unset CC_ACCOUNT_BEDROCK_REGION
export AWS_REGION="user-own-region"
cc-account use bedrock >/dev/null 2>&1
cc-account off >/dev/null
if [[ -n "${AWS_REGION:-}" ]]; then
  print "OK   [素材の無い AWS_REGION を off が消さない]"
else
  print "NG   [素材の無い AWS_REGION を off が消した]"
  (( fails++ ))
fi

print ""
if (( fails == 0 )); then
  print "PASS 全ケース期待どおり"
else
  print "FAIL $fails 件が不一致"
  exit 1
fi
