import { Component, type ErrorInfo, type ReactNode } from "react";

import { logger } from "../utils/logger";

type Props = { children: ReactNode };
type State = { hasError: boolean };

// 组件级错误边界：捕获渲染异常，记录日志并展示兜底 UI。
export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    logger.error("component error", { message: error.message, info });
  }

  render(): ReactNode {
    if (this.state.hasError) {
      return <div className="p-8 text-red-600">页面出错了，请刷新重试。</div>;
    }
    return this.props.children;
  }
}
