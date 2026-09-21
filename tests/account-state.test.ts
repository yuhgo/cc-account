// statusline/account-state.ts の回帰テスト。
//
// 使い方: bun test tests/account-state.test.ts
//
// env を引数で注入するので、実環境の環境変数には一切触れない。

import { expect, test } from "bun:test";
import { getAccountState } from "../statusline/account-state.ts";

const HOME = "/home/testuser";

test("CLAUDE_CONFIG_DIR 未設定なら personal / default", () => {
  const s = getAccountState({ HOME });
  expect(s.account).toBe("personal");
  expect(s.provider).toBe("anthropic");
  expect(s.configDir).toBe(`${HOME}/.claude`);
  expect(s.source).toBe("default");
});

test(".claude-adixi を含む config_dir なら adixi / env", () => {
  const s = getAccountState({ HOME, CLAUDE_CONFIG_DIR: `${HOME}/.claude-adixi` });
  expect(s.account).toBe("adixi");
  expect(s.source).toBe("env");
  expect(s.configDir).toBe(`${HOME}/.claude-adixi`);
});

test("Bedrock が truthy なら provider=bedrock", () => {
  for (const v of ["1", "true", "yes", "on", "TRUE", " 1 "]) {
    expect(getAccountState({ HOME, CLAUDE_CODE_USE_BEDROCK: v }).provider).toBe("bedrock");
  }
});

test("Bedrock が falsy なら provider=anthropic", () => {
  for (const v of ["0", "false", "", "no"]) {
    expect(getAccountState({ HOME, CLAUDE_CODE_USE_BEDROCK: v }).provider).toBe("anthropic");
  }
});

test("provider と account は独立の軸（Bedrock は場所非依存）", () => {
  // 旧 API は bedrock のとき account を潰していたが、データとしては両方返す。
  // 「どちらを優先して出すか」は statusline 側の裁量。
  const s = getAccountState({
    HOME,
    CLAUDE_CODE_USE_BEDROCK: "1",
    CLAUDE_CONFIG_DIR: `${HOME}/.claude-adixi`,
  });
  expect(s.provider).toBe("bedrock");
  expect(s.account).toBe("adixi");
});

test("空文字の CLAUDE_CONFIG_DIR は invalid として示す", () => {
  const s = getAccountState({ HOME, CLAUDE_CONFIG_DIR: "" });
  expect(s.source).toBe("invalid");
  expect(s.configDir).toBe(`${HOME}/.claude`);
});

test("未知の config_dir は personal 扱い（--no-file と同じ推測）", () => {
  const s = getAccountState({ HOME, CLAUDE_CONFIG_DIR: `${HOME}/.claude-somenewname` });
  expect(s.account).toBe("personal");
  expect(s.source).toBe("env");
});

test("会社の目印と短縮名は環境変数で差し替えられる", () => {
  const s = getAccountState({
    HOME,
    CLAUDE_CONFIG_DIR: `${HOME}/.claude-example`,
    CC_ACCOUNT_ADIXI_DIR: ".claude-example",
    CC_ACCOUNT_ORG_LABEL: "example",
  });
  expect(s.account).toBe("example");
});

test("表示に関わる値（色・絵文字・ラベル）を返さない", () => {
  // 責務の境界を固定するテスト。表示は statusline 側の裁量なので、
  // ここに label や色が生えたら設計が崩れている。
  const s = getAccountState({ HOME });
  expect(Object.keys(s).sort()).toEqual(["account", "configDir", "provider", "source"]);
  expect(JSON.stringify(s)).not.toContain("\x1b[");
});
