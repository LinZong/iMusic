import { useEffect, useRef, useState } from "react";
import {
  canRetry,
  createUploadEntry,
  type UploadEntry,
} from "../domain/uploadQueue";
import type { Message } from "../i18n";
import { upload } from "../services/uploadApi";
import type { Configuration } from "../domain/uploadConfiguration";
import { transferErrorMessage } from "../services/transferErrors";

/** Queue state and commands exposed to upload components without exposing transport internals. */
interface UploadQueue {
  /** Ordered file occurrences and their individual validation or transfer results. */
  entries: UploadEntry[];
  /** Whether one sequential batch is active. */
  busy: boolean;
  /** Adds distinct occurrences after native extension and size validation. */
  addFiles: (files: File[]) => void;
  /** Sends waiting files sequentially, stopping on a network error or expired authorization. */
  startUpload: () => Promise<void>;
  /** Aborts the active request and marks the remainder of this batch as cancelled. */
  cancelUpload: () => void;
  /** Resets a recoverable failed or cancelled occurrence to waiting. */
  retryEntry: (id: number) => void;
  /** Removes one occurrence while no batch is active. */
  removeEntry: (id: number) => void;
}

/** Owns the file queue and its cancellable upload loop, independently of pairing form state. */
export function useUploadQueue(
  config: Configuration | undefined,
  token: string | undefined,
  onStart: () => void,
  onFailure: (message: Message) => void,
): UploadQueue {
  /** File occurrences retained when a session expires and the user pairs again. */
  const [entries, setEntries] = useState<UploadEntry[]>([]);
  /** Rendered batch activity controlling file selection and row actions. */
  const [busy, setBusy] = useState(false);
  /** Monotonic source of identities, allocated outside React's state updater. */
  const counter = useRef(0);
  /** Synchronous guard preventing duplicate loops before React rerenders. */
  const running = useRef(false);
  /** Active batch cancellation propagated to the transport request. */
  const controller = useRef<AbortController | null>(null);

  useEffect(() => () => controller.current?.abort(), []);

  /** Validates a batch of selections without mutating previously queued occurrences. */
  function addFiles(files: File[]) {
    if (!config || !token || running.current) return;
    const added = files.map((file) =>
      createUploadEntry(++counter.current, file, config),
    );
    setEntries((previous) => [...previous, ...added]);
  }

  /** Updates one occurrence by identity without changing another selection of the same file. */
  function update(id: number, changes: Partial<UploadEntry>) {
    setEntries((previous) =>
      previous.map((entry) =>
        entry.id === id ? { ...entry, ...changes } : entry,
      ),
    );
  }

  /** Runs one batch against its captured credential and preserves remaining entries after failure. */
  async function startUpload() {
    if (!config || !token || running.current) return;
    const pending = entries.filter((entry) => entry.status === "waiting");
    if (!pending.length) return;
    const request = new AbortController();
    running.current = true;
    controller.current = request;
    setBusy(true);
    onStart();
    try {
      for (const entry of pending) {
        if (request.signal.aborted) {
          update(entry.id, { status: "cancelled" });
          continue;
        }
        update(entry.id, {
          status: "uploading",
          progress: 0,
          error: undefined,
        });
        try {
          await upload(entry.file, token, request.signal, (progress) => {
            if (!request.signal.aborted) update(entry.id, { progress });
          });
          update(entry.id, { status: "received", progress: 100 });
        } catch (value) {
          const message = request.signal.aborted
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
    } finally {
      running.current = false;
      setBusy(false);
      controller.current = null;
    }
  }

  /** Retries only recoverable entries and never changes a queue while a batch is active. */
  function retryEntry(id: number) {
    if (running.current) return;
    setEntries((previous) =>
      previous.map((entry) =>
        entry.id === id && canRetry(entry)
          ? { ...entry, status: "waiting", progress: 0, error: undefined }
          : entry,
      ),
    );
  }

  /** Removes exactly one selected occurrence while preserving all other queue identities. */
  function removeEntry(id: number) {
    if (!running.current)
      setEntries((previous) => previous.filter((entry) => entry.id !== id));
  }

  return {
    entries,
    busy,
    addFiles,
    startUpload,
    cancelUpload: () => controller.current?.abort(),
    retryEntry,
    removeEntry,
  };
}
