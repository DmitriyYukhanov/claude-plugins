/**
 * Telegram alert service — Node.js / TypeScript variant.
 *
 * Reference implementation. Adapt to your project's style and structure.
 * Zero dependencies — uses built-in fetch (Node 18+).
 */

const ENV = process.env.ENVIRONMENT ?? "development";
const MAX_DEDUP_KEYS = 10_000;

let _alertService: AlertService | null = null;

export function getAlertService(): AlertService | null {
  return _alertService;
}

export function initAlertService(
  botToken: string,
  chatId: string,
  threadId?: number,
): AlertService {
  _alertService = new AlertService(botToken, chatId, threadId);
  return _alertService;
}

// -- Core service ---------------------------------------------------------

export class AlertService {
  private readonly url: string;
  private readonly chatId: string;
  private readonly threadId?: number;
  private readonly seen = new Set<string>();

  constructor(botToken: string, chatId: string, threadId?: number) {
    this.chatId = chatId;
    this.threadId = threadId;
    this.url = `https://api.telegram.org/bot${botToken}/sendMessage`;
  }

  /** Send an alert. If dedup_key was already sent, skip silently. */
  async sendAlert(text: string, dedupKey?: string): Promise<void> {
    try {
      if (dedupKey != null) {
        if (this.seen.has(dedupKey)) return;
        if (this.seen.size >= MAX_DEDUP_KEYS) this.seen.clear();
        this.seen.add(dedupKey);
      }

      const payload: Record<string, unknown> = {
        chat_id: this.chatId,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      };
      if (this.threadId != null) {
        payload.message_thread_id = this.threadId;
      }

      await fetch(this.url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      // Swallow — alert failures must never affect the app.
      // Do NOT use console.error here — it may trigger the logging hook
      // and create an infinite loop. Use console.debug instead.
      console.debug("Failed to send Telegram alert");
    }
  }

  /** Format and send an error alert with dedup by error message + stack. */
  async sendErrorAlert(err: Error, context = ""): Promise<void> {
    // Dedup by first meaningful stack frame.
    const stackLine = err.stack?.split("\n")[1]?.trim() ?? "unknown";
    const dedupKey = `${err.name}:${stackLine.slice(0, 100)}`;

    let stackText = err.stack ?? String(err);
    if (stackText.length > 3200) {
      stackText = stackText.slice(0, 3200) + "\n... (truncated)";
    }

    const ctxLine = context ? `Context: ${context}\n` : "";
    const block = `Env: ${ENV}\nError: ${err.name}\n${ctxLine}\n${stackText}`;
    const text = `\u{1F534} <b>Error</b>\n<pre>${escapeHtml(block)}</pre>`;
    await this.sendAlert(text, dedupKey);
  }

  async sendWarningAlert(message: string, dedupKey?: string): Promise<void> {
    const block = `Env: ${ENV}\n${message}`;
    const text = `\u{1F7E1} <b>Warning</b>\n<pre>${escapeHtml(block.slice(0, 3500))}</pre>`;
    await this.sendAlert(text, dedupKey);
  }

  /** Startup/shutdown — always sent (no dedup). */
  async sendLifecycleAlert(event: string): Promise<void> {
    const block = `${event}\nEnv: ${ENV}`;
    const text = `\u{1F7E2}\n<pre>${escapeHtml(block)}</pre>`;
    await this.sendAlert(text);
  }

}

// -- Helpers --------------------------------------------------------------

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// -- Global error hooks ---------------------------------------------------

/**
 * Call once at startup to wire unhandled errors into alerts.
 * Works in Node.js — for Bun/Deno, adapt the event names.
 */
export function setupGlobalErrorAlerts(): void {
  const svc = getAlertService();
  if (!svc) return;

  process.on("uncaughtException", (err) => {
    // Fire-and-forget: .catch prevents unhandled rejection from the alert itself.
    svc.sendErrorAlert(err, "uncaughtException").catch(() => {});
    // Re-throw or exit per your app's policy.
  });

  process.on("unhandledRejection", (reason) => {
    const err = reason instanceof Error ? reason : new Error(String(reason));
    svc.sendErrorAlert(err, "unhandledRejection").catch(() => {});
  });
}

// -- Integration examples -------------------------------------------------
//
// === Express ===
//
// import { initAlertService, getAlertService, setupGlobalErrorAlerts } from "./alert_service";
//
// const app = express();
//
// // Startup
// if (process.env.ALERT_BOT_TOKEN && process.env.ALERT_CHAT_ID) {
//   const svc = initAlertService(
//     process.env.ALERT_BOT_TOKEN,
//     process.env.ALERT_CHAT_ID,
//     process.env.ALERT_THREAD_ID ? Number(process.env.ALERT_THREAD_ID) : undefined,
//   );
//   setupGlobalErrorAlerts();
//   svc.sendLifecycleAlert("Application started");
// }
//
// // Error middleware (MUST be last app.use)
// app.use((err: Error, req: Request, res: Response, _next: NextFunction) => {
//   const svc = getAlertService();
//   svc?.sendErrorAlert(err, `${req.method} ${req.path}`).catch(() => {});
//   res.status(500).json({ error: "Internal server error" });
// });
//
// // Graceful shutdown
// process.on("SIGTERM", async () => {
//   const svc = getAlertService();
//   if (svc) await svc.sendLifecycleAlert("Application shutting down");
//   process.exit(0);
// });
//
// === NestJS ===
//
// // Create an exception filter:
// @Catch()
// export class TelegramAlertFilter implements ExceptionFilter {
//   catch(exception: Error, host: ArgumentsHost) {
//     const ctx = host.switchToHttp();
//     const req = ctx.getRequest();
//     const svc = getAlertService();
//     svc?.sendErrorAlert(exception, `${req.method} ${req.url}`).catch(() => {});
//     // ... return appropriate response
//   }
// }
//
// // Register globally in main.ts:
// app.useGlobalFilters(new TelegramAlertFilter());
