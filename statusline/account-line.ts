// Claude アカウント / プロバイダを statusline の 1 行として返す。
//
// bin/cc-account.py の --no-file と同じ判定を環境変数だけで行う。
// statusline は描画のたびに走るため、ここでは子プロセスを起こさずファイルも読まない。
// 判定ロジックを変えるときは cc-account.py 側と揃えること。
//
// 使い方（呼び出し側の statusline から）:
//   import { getAccountInfo, renderAccountLine } from "<path>/statusline/account-line.ts";
//   const line = renderAccountLine();
//   if (line) output += "\n" + line;

// Kanagawa Wave 準拠の色。呼び出し側と揃えたいときは renderAccountLine に上書きを渡す。
const DEFAULT_COLORS = {
  gray: "\x1b[38;2;114;113;105m", // fujiGray     #727169
  orange: "\x1b[38;2;255;160;102m", // surimiOrange #FFA066
  yellow: "\x1b[38;2;230;195;132m", // carpYellow   #E6C384
  reset: "\x1b[0m",
} as const;

export type AccountColors = {
  gray: string;
  orange: string;
  yellow: string;
  reset: string;
};

export type AccountInfo = {
  /** 表示ラベル（絵文字込み） */
  label: string;
  /** 色種別。呼び出し側が独自パレットを当てたいとき用 */
  tone: "personal" | "adixi" | "bedrock";
};

/** 会社用の設定置き場を示す目印。zsh 側の CC_ACCOUNT_ADIXI_DIR と対応する。 */
const ADIXI_MARKER = ".claude-adixi";

function isTruthy(value: string | undefined): boolean {
  const v = (value ?? "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes" || v === "on";
}

export function getAccountInfo(
  env: Record<string, string | undefined> = process.env,
): AccountInfo {
  // Bedrock は設定置き場と独立の軸。有効なら最優先で示す。
  if (isTruthy(env.CLAUDE_CODE_USE_BEDROCK)) {
    return { label: "☁️ bedrock", tone: "bedrock" };
  }

  const configDir = env.CLAUDE_CONFIG_DIR ?? "";
  if (configDir.includes(ADIXI_MARKER)) {
    return { label: "👤 adixi", tone: "adixi" };
  }
  return { label: "👤 personal", tone: "personal" };
}

export function renderAccountLine(
  env: Record<string, string | undefined> = process.env,
  colors: AccountColors = DEFAULT_COLORS,
): string {
  const info = getAccountInfo(env);
  const color =
    info.tone === "bedrock"
      ? colors.yellow
      : info.tone === "adixi"
        ? colors.orange
        : colors.gray;
  return `${color}${info.label}${colors.reset}`;
}
