#!/bin/bash
# cc-account.py の回帰テスト。
#
# 使い方: bash tests/run-cc-account-tests.sh
# ケース表: cc-account.cases.tsv （"期待値<TAB>説明<TAB>fixture名<TAB>追加env<TAB>CLI引数"）
#   期待値は JSON の一部を取り出して比較する（比較対象キーはケースごとに TSV で指定する）
#
# 注意: 追加env 列は run_case 内で未クォート展開している（複数の KEY=VALUE を
# word splitting で渡すための意図的な設計）。したがって **空白を含まない KEY=VALUE のみ**
# 許容する。空白入りの値を渡したくなったら、展開方法ごと作り直すこと。
# 追加env が無いケースは空フィールドではなく "-" を置く（bash の read が
# 空フィールドでずれるため）。
#
# 各ケースは一時ディレクトリに fixture（HOME / CLAUDE_CONFIG_DIR 配下の .claude.json）を作り、
# 実ユーザーの ~/.claude.json には一切触れずに HOME / CLAUDE_CONFIG_DIR を差し替えて実行する。
# テスト後に一時ディレクトリを掃除する。

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../bin/cc-account.py"
CASES="$HERE/cc-account.cases.tsv"

[ -f "$SCRIPT" ] || { echo "スクリプトが見つからない: $SCRIPT" >&2; exit 1; }
[ -f "$CASES" ]  || { echo "ケース表が見つからない: $CASES" >&2; exit 1; }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cc-account-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail=0
total=0

# fixture 準備関数群 ---------------------------------------------------------

setup_personal() {
  # 個人: CLAUDE_CONFIG_DIR 未設定、~/.claude.json に個人の組織名
  local fixture_home="$1"
  mkdir -p "$fixture_home"
  cat > "$fixture_home/.claude.json" <<'EOF'
{"oauthAccount": {"organizationName": "someone@example.com's Organization", "accountUuid": "dummy"}, "someToken": "should-not-be-read"}
EOF
}

setup_adixi() {
  # 会社: CLAUDE_CONFIG_DIR=<tmp>/.claude-adixi、そこに .claude.json で ADiXi Inc.
  local fixture_home="$1"
  local config_dir="$fixture_home/.claude-adixi"
  mkdir -p "$config_dir"
  cat > "$config_dir/.claude.json" <<'EOF'
{"oauthAccount": {"organizationName": "ADiXi Inc.", "accountUuid": "dummy"}, "someToken": "should-not-be-read"}
EOF
}

setup_bedrock() {
  # Bedrock 有効。config_dir 側の判定 (personal fixture) と組み合わせて場所非依存を確認
  setup_personal "$1"
}

setup_missing() {
  # config 不在: .claude.json が無い
  local fixture_home="$1"
  mkdir -p "$fixture_home"
}

# ケース実行 ------------------------------------------------------------------

run_case() {
  local case_id="$1" fixture="$2" extra_env="$3" jq_field="$4" expected="$5"
  # extra_env の "-" は「追加 env なし」の意味（TSV で空フィールドを避けるためのプレースホルダ）
  [ "$extra_env" = "-" ] && extra_env=""

  total=$((total + 1))
  local fixture_home="$TMP_ROOT/$case_id"
  rm -rf "$fixture_home"
  mkdir -p "$fixture_home"

  "setup_${fixture}" "$fixture_home"

  local unset_config_dir=1
  local config_dir_env=""
  if [ "$fixture" = "adixi" ]; then
    config_dir_env="$fixture_home/.claude-adixi"
    unset_config_dir=0
  fi

  local out exit_code
  if [ "$unset_config_dir" -eq 1 ]; then
    out=$(env -u CLAUDE_CONFIG_DIR HOME="$fixture_home" $extra_env python3 "$SCRIPT" --json 2>&1)
    exit_code=$?
  else
    out=$(HOME="$fixture_home" CLAUDE_CONFIG_DIR="$config_dir_env" $extra_env python3 "$SCRIPT" --json 2>&1)
    exit_code=$?
  fi

  if [ "$exit_code" -ne 0 ]; then
    fail=$((fail + 1))
    printf 'NG [%s] exit_code=%s (期待 0) output=%s\n' "$case_id" "$exit_code" "$out"
    return
  fi

  local got
  got=$(printf '%s' "$out" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('__PARSE_ERROR__')
    sys.exit(0)
print(d.get('$jq_field', '__MISSING__'))
")

  if [ "$got" != "$expected" ]; then
    fail=$((fail + 1))
    printf 'NG [%s] %s=%s (期待 %s) output=%s\n' "$case_id" "$jq_field" "$got" "$expected" "$out"
  fi
}

# TSV を読んで実行 ------------------------------------------------------------

while IFS=$'\t' read -r case_id fixture extra_env jq_field expected; do
  [ -z "${case_id:-}" ] && continue
  case "$case_id" in \#*) continue ;; esac
  run_case "$case_id" "$fixture" "$extra_env" "$jq_field" "$expected"
done < "$CASES"

# --no-file フラグの追加確認（config 不在でも exit 0、account=unknown ではなく personal 推測になること）
total=$((total + 1))
no_file_home="$TMP_ROOT/no-file-check"
mkdir -p "$no_file_home"
out=$(env -u CLAUDE_CONFIG_DIR HOME="$no_file_home" python3 "$SCRIPT" --json --no-file 2>&1)
exit_code=$?
if [ "$exit_code" -ne 0 ]; then
  fail=$((fail + 1))
  printf 'NG [no-file-personal] exit_code=%s (期待 0) output=%s\n' "$exit_code" "$out"
else
  got=$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('account','__MISSING__'))")
  if [ "$got" != "personal" ]; then
    fail=$((fail + 1))
    printf 'NG [no-file-personal] account=%s (期待 personal) output=%s\n' "$got" "$out"
  fi
fi

# 未知の config_dir を --no-file で見たとき、personal と断定せず unknown になること
# （会社側のディレクトリ名を変えたときの誤表示を防ぐ回帰テスト）
total=$((total + 1))
unknown_home="$TMP_ROOT/unknown-config-dir"
mkdir -p "$unknown_home"
out=$(HOME="$unknown_home" CLAUDE_CONFIG_DIR="$unknown_home/.claude-somenewname" python3 "$SCRIPT" --json --no-file 2>&1)
got=$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('account','__MISSING__'))")
if [ "$got" != "unknown" ]; then
  fail=$((fail + 1))
  printf 'NG [no-file-unknown-config-dir] account=%s (期待 unknown) output=%s\n' "$got" "$out"
fi

# CLAUDE_CONFIG_DIR が空文字のとき、未設定と区別して source=invalid になること
total=$((total + 1))
empty_home="$TMP_ROOT/empty-config-dir"
mkdir -p "$empty_home"
out=$(HOME="$empty_home" CLAUDE_CONFIG_DIR="" python3 "$SCRIPT" --json 2>&1)
exit_code=$?
got=$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('source','__MISSING__'))")
if [ "$exit_code" -ne 0 ] || [ "$got" != "invalid" ]; then
  fail=$((fail + 1))
  printf 'NG [empty-config-dir] source=%s exit=%s (期待 invalid / 0) output=%s\n' "$got" "$exit_code" "$out"
fi

# 会社組織名を CC_ACCOUNT_ORG_NAME / CC_ACCOUNT_ORG_LABEL で差し替えられること
# （別の組織でもコードを触らず使えるようにした分の回帰テスト）
total=$((total + 1))
org_home="$TMP_ROOT/custom-org"
org_dir="$org_home/.claude-adixi"
mkdir -p "$org_dir"
printf '%s\n' '{"oauthAccount": {"organizationName": "Example Inc."}}' > "$org_dir/.claude.json"
out=$(HOME="$org_home" CLAUDE_CONFIG_DIR="$org_dir" \
      CC_ACCOUNT_ORG_NAME="Example Inc." CC_ACCOUNT_ORG_LABEL="example" \
      python3 "$SCRIPT" --json 2>&1)
got=$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('account','__MISSING__'))")
if [ "$got" != "example" ]; then
  fail=$((fail + 1))
  printf 'NG [custom-org-name] account=%s (期待 example) output=%s\n' "$got" "$out"
fi

if [ "$fail" -eq 0 ]; then
  printf '\033[32mPASS\033[0m %d ケース すべて期待どおり\n' "$total"
  exit 0
fi
printf '\033[31mFAIL\033[0m %d / %d ケースが不一致\n' "$fail" "$total"
exit 1
