// 统一前端日志：dev 输出 console，prod 可接 Sentry。
// 禁止在组件/hooks 直接用 console.log（见 .claude/rules/frontend-runtime.md）。
export const logger = {
  info: (msg: string, ctx?: object): void => {
    // eslint-disable-next-line no-console
    if (import.meta.env.DEV) console.info(`[INFO] ${msg}`, ctx ?? "");
  },
  warn: (msg: string, ctx?: object): void => {
    console.warn(`[WARN] ${msg}`, ctx ?? "");
  },
  error: (msg: string, ctx?: object): void => {
    console.error(`[ERROR] ${msg}`, ctx ?? "");
  },
};
