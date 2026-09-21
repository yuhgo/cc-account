// Claude のアカウント / プロバイダの「現在の状態」を返す。
//
// bin/cc-account.py の --no-file と同じ判定を環境変数だけで行う。
// statusline は描画のたびに走るため、子プロセスを起こさずファイルも読まない。
// 判定ロジックを変えるときは cc-account.py 側と揃えること。
//
// このモジュールは **データだけ** を返す。絵文字・ラベル・色・行の組み立ては
// すべて呼び出し側（statusline）の裁量とする。
//
// 使い方:
//   import { getAccountState } from "<path>/statusline/account-state.ts";
//   const { account, provider } = getAccountState();
//   const label = provider === "bedrock" ? `☁️ ${provider}` : `👤 ${account}`;

export type AccountState = {
  /** 短縮アカウント名。既定は "personal" / "adixi"、判定できなければ "unknown" */
  account: string;
  /** 使用中のプロバイダ */
  provider: "anthropic" | "bedrock";
  /** 実際に使われている設定ディレクトリの絶対パス */
  configDir: string;
  /**
   * configDir の出どころ。
   * - default: CLAUDE_CONFIG_DIR 未設定（既定の ~/.claude）
   * - env:     CLAUDE_CONFIG_DIR あり
   * - invalid: CLAUDE_CONFIG_DIR が空文字（direnv 等の設定ミス）
   */
  source: "default" | "env" | "invalid";
};

/** 会社用の設定置き場を示す目印。zsh 側の CC_ACCOUNT_ADIXI_DIR と対応する。 */
const DEFAULT_WORK_MARKER = ".claude-adixi";
/** 上記に対応する短縮名。bin/cc-account.py の DEFAULT_ORG_LABEL と揃える。 */
const DEFAULT_WORK_LABEL = "adixi";

function isTruthy(value: string | undefined): boolean {
  const v = (value ?? "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes" || v === "on";
}

export function getAccountState(
  env: Record<string, string | undefined> = process.env,
): AccountState {
  const provider: "anthropic" | "bedrock" = isTruthy(env.CLAUDE_CODE_USE_BEDROCK)
    ? "bedrock"
    : "anthropic";

  const rawConfigDir = env.CLAUDE_CONFIG_DIR;
  const home = env.HOME ?? "";

  let configDir: string;
  let source: AccountState["source"];
  if (rawConfigDir === undefined) {
    configDir = `${home}/.claude`;
    source = "default";
  } else if (rawConfigDir.trim() === "") {
    // 空文字は「未設定」と区別する。既定に落として黙るのではなく、
    // 呼び出し側が設定ミスに気づけるよう invalid として示す。
    configDir = `${home}/.claude`;
    source = "invalid";
  } else {
    configDir = rawConfigDir.trim();
    source = "env";
  }

  // 会社用の目印と短縮名は環境変数で上書きできる（別組織でもそのまま使えるように）。
  const workMarker = env.CC_ACCOUNT_ADIXI_DIR?.trim()
    ? env.CC_ACCOUNT_ADIXI_DIR.trim()
    : DEFAULT_WORK_MARKER;
  const workLabel = env.CC_ACCOUNT_ORG_LABEL?.trim() || DEFAULT_WORK_LABEL;

  const account = configDir.includes(workMarker) ? workLabel : "personal";

  return { account, provider, configDir, source };
}
