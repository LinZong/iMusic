import type { Message } from "../i18n";
import type { Configuration } from "./uploadConfiguration";

/** One file's transfer lifecycle; received means HTTP acceptance, not completed native import. */
export type UploadStatus =
  "waiting" | "uploading" | "received" | "failed" | "cancelled";

/** A selected file occurrence, independent of other selections with the same filename or bytes. */
export interface UploadEntry {
  /** Page-local occurrence identity used for rendering, retries, and removal. */
  id: number;
  /** Browser file whose original name and bytes are sent to the native listener. */
  file: File;
  /** Transfer lifecycle state controlling the row's label and available actions. */
  status: UploadStatus;
  /** Integer upload percentage; 100 is reserved for successful HTTP acceptance. */
  progress: number;
  /** Translation key describing a validation or transfer error for this occurrence. */
  error?: Message;
  /** Whether immutable file validation failed, preventing retry of the same occurrence. */
  invalid: boolean;
}

/** Validates one file against native capabilities without changing its name, contents, or identity. */
export function createUploadEntry(
  id: number,
  file: File,
  config: Configuration,
): UploadEntry {
  const extension = file.name.includes(".")
    ? file.name.split(".").at(-1)!.toLowerCase()
    : "";
  const error: Message | undefined = !config.extensions.includes(extension)
    ? "unsupported"
    : file.size > config.maxFileSize
      ? "tooLarge"
      : undefined;
  return {
    id,
    file,
    status: error ? "failed" : "waiting",
    progress: 0,
    error,
    invalid: !!error,
  };
}

/** Allows retry only for recoverable transfer failures or cancellations, never invalid files. */
export function canRetry(entry: UploadEntry): boolean {
  return (
    !entry.invalid &&
    (entry.status === "failed" || entry.status === "cancelled")
  );
}
