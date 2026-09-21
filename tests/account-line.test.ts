// statusline/account-line.ts の回帰テスト。
//
// 使い方: bun test tests/account-line.test.ts
//
// env を引数で注入するので、実環境の環境変数には一切触れない。

import { expect, test } from "bun:test";
import { getAccountInfo, renderAccountLine } from "../statusline/account-line.ts";

test("CLAUDE_CONFIG_DIR 未設定なら personal", () => {
  expect(getAccountInfo({})).toEqual({ label: "👤 personal", tone: "personal" });
});

test(".claude-adixi を含む config_dir なら adixi", () => {
  expect(getAccountInfo({ CLAUDE_CONFIG_DIR: "/Users/x/.claude-adixi" }).tone).toBe("adixi");
});

test("Bedrock が truthy なら bedrock", () => {
  for (const v of ["1", "true", "yes", "on", "TRUE", " 1 "]) {
    expect(getAccountInfo({ CLAUDE_CODE_USE_BEDROCK: v }).tone).toBe("bedrock");
  }
});

test("Bedrock が falsy なら bedrock にしない", () => {
  for (const v of ["0", "false", "", "no"]) {
    expect(getAccountInfo({ CLAUDE_CODE_USE_BEDROCK: v }).tone).not.toBe("bedrock");
  }
});

test("Bedrock は設定置き場より優先される（場所非依存）", () => {
  const info = getAccountInfo({
    CLAUDE_CODE_USE_BEDROCK: "1",
    CLAUDE_CONFIG_DIR: "/Users/x/.claude-adixi",
  });
  expect(info.tone).toBe("bedrock");
});

test("未知の config_dir は personal 扱い（statusline は落とさない）", () => {
  // cc-account.py --no-file は unknown を返すが、statusline は常時表示のため
  // 表示を欠けさせず personal にフォールバックする。挙動差を意図として固定しておく。
  expect(getAccountInfo({ CLAUDE_CONFIG_DIR: "/Users/x/.claude-somenewname" }).tone).toBe(
    "personal",
  );
});

test("renderAccountLine は色で包んでリセットする", () => {
  const line = renderAccountLine({});
  expect(line).toContain("👤 personal");
  expect(line.endsWith("\x1b[0m")).toBe(true);
});

test("色は差し替えできる", () => {
  const line = renderAccountLine(
    { CLAUDE_CODE_USE_BEDROCK: "1" },
    { gray: "<g>", orange: "<o>", yellow: "<y>", reset: "<r>" },
  );
  expect(line).toBe("<y>☁️ bedrock<r>");
});
