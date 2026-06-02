import { logger } from "../utils/logger";

export type WsHandlers = {
  onMessage: (data: unknown) => void;
  onOpen?: () => void;
  onClose?: () => void;
};

// 通用 WebSocket 客户端：建连 + 收发 + 消息反序列化。
// 业务层在 hooks 中调用，组件不直接碰（见 .claude/rules/frontend.md 分层边界）。
export function connectWs(url: string, handlers: WsHandlers): WebSocket {
  const ws = new WebSocket(url);
  ws.onopen = (): void => {
    logger.info("ws open", { url });
    handlers.onOpen?.();
  };
  ws.onmessage = (e: MessageEvent): void => {
    try {
      handlers.onMessage(JSON.parse(e.data));
    } catch (err) {
      logger.warn("invalid ws message", { err });
    }
  };
  ws.onclose = (): void => {
    logger.info("ws closed");
    handlers.onClose?.();
  };
  return ws;
}

export function sendWs(ws: WebSocket, message: object): void {
  ws.send(JSON.stringify(message));
}
