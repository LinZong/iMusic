import type { UploadEntry } from "../domain/uploadQueue";
import type { Message } from "../i18n";
import { transferErrorMessage } from "./transferErrors";

/** Narrow upload dependency; batch policy does not depend on XMLHttpRequest or React. */
export type UploadTransport = (
  file: File,
  token: string,
  signal: AbortSignal,
  progress: (value: number) => void,
) => Promise<void>;

/** Inputs and event sinks for one sequential, cancellable batch. */
export interface UploadBatch {
  /** Waiting occurrences captured when the user starts this batch. */
  pending: UploadEntry[];
  /** Credential captured for this batch rather than read from later pairing state. */
  token: string;
  /** Shared cancellation signal for the active request and remaining entries. */
  signal: AbortSignal;
  /** File transport supplied by the caller. */
  transport: UploadTransport;
  /** Publishes occurrence changes without owning a UI state container. */
  update: (id: number, changes: Partial<UploadEntry>) => void;
  /** Reports session-wide failures while leaving unsent entries available for retry. */
  onFailure: (message: Message) => void;
}

/** Runs transfer policy independently of React rendering, queue editing, and pairing forms. */
export async function runUploadBatch({
  pending,
  token,
  signal,
  transport,
  update,
  onFailure,
}: UploadBatch): Promise<void> {
  for (const entry of pending) {
    if (signal.aborted) {
      update(entry.id, { status: "cancelled" });
      continue;
    }
    update(entry.id, {
      status: "uploading",
      progress: 0,
      error: undefined,
    });
    try {
      await transport(entry.file, token, signal, (progress) => {
        if (!signal.aborted) update(entry.id, { progress });
      });
      update(entry.id, { status: "received", progress: 100 });
    } catch (value) {
      const message = signal.aborted
        ? "cancelled"
        : transferErrorMessage(value);
      update(entry.id, {
        status: message === "cancelled" ? "cancelled" : "failed",
        error: message,
      });
      if (message === "expired" || message === "networkError") {
        onFailure(message);
        break;
      }
    }
  }
}
