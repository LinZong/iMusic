import type { Message } from "../i18n";
import type { Configuration } from "../domain/uploadConfiguration";
/** Transfer failure carrying a shared translation key rather than a hardcoded UI message. */
export class TransferError extends Error {
  /** Creates a transfer failure; messageID identifies the localized explanation shown by the UI. */
  constructor(
    /** Shared translation key describing this failure. */
    public readonly messageID: Message,
  ) {
    super(messageID);
  }
}
/** Loads and validates app language and upload limits; the signal cancels an obsolete page request. */
export async function configuration(
  signal: AbortSignal,
): Promise<Configuration> {
  const response = await fetch("/api/config", { signal, cache: "no-store" });
  if (!response.ok) throw new TransferError("networkError");
  const value: Configuration = await response.json();
  if (
    !["en", "zh-Hans", "zh-Hant"].includes(value.language) ||
    !Array.isArray(value.extensions) ||
    !value.extensions.every((extension) => /^[a-z0-9]+$/.test(extension)) ||
    !Number.isSafeInteger(value.maxFileSize) ||
    value.maxFileSize <= 0
  )
    throw new TransferError("networkError");
  return value;
}
/** Exchanges the six-digit pairing code for a session-scoped bearer token; rejects invalid codes. */
export async function pair(code: string, signal: AbortSignal): Promise<string> {
  const response = await fetch("/pair", {
    method: "POST",
    body: code,
    signal,
    cache: "no-store",
  });
  if (response.status === 401) throw new TransferError("wrongCode");
  if (!response.ok) throw new TransferError("networkError");
  return response.text();
}
/**
 * Streams one file using the paired token, reports progress from 0 through 99, and supports cancellation.
 * Resolves only after the app accepts the complete body; acceptance does not imply native import finished.
 */
export function upload(
  file: File,
  token: string,
  signal: AbortSignal,
  progress: (value: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const abort = () => xhr.abort();
    const finish = (error?: Message) => {
      signal.removeEventListener("abort", abort);
      if (error) reject(new TransferError(error));
      else resolve();
    };
    if (signal.aborted) {
      reject(new TransferError("cancelled"));
      return;
    }
    xhr.open("POST", `/upload?${new URLSearchParams({ name: file.name })}`);
    xhr.setRequestHeader("Authorization", `Bearer ${token}`);
    xhr.setRequestHeader("Content-Type", "application/octet-stream");
    xhr.timeout = 300_000;
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && event.total > 0)
        progress(Math.min(99, Math.floor((event.loaded / event.total) * 100)));
    };
    xhr.onload = () =>
      finish(
        xhr.status === 202
          ? undefined
          : xhr.status === 401
            ? "expired"
            : xhr.status === 413
              ? "tooLarge"
              : xhr.status === 400
                ? "unsupported"
                : "failed",
      );
    xhr.onerror = () => finish("networkError");
    xhr.ontimeout = () => finish("networkError");
    xhr.onabort = () => finish("cancelled");
    signal.addEventListener("abort", abort, { once: true });
    xhr.send(file);
  });
}
