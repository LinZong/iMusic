import { canRetry, type UploadEntry } from "../../domain/uploadQueue";
import type { Language, Strings } from "../../i18n";

/** A single queue occurrence and its presentation-only row commands. */
interface UploadQueueItemProps {
  /** File occurrence whose transfer state is displayed. */
  entry: UploadEntry;
  /** Active batch flag used to hide mutating row actions. */
  busy: boolean;
  /** Locale used to display decimal file sizes. */
  language: Language;
  /** Localized status, action, and accessibility labels. */
  strings: Strings;
  /** Retries the occurrence identified by its page-local identity. */
  onRetry: (id: number) => void;
  /** Removes only this occurrence. */
  onRemove: (id: number) => void;
}

/** Renders file metadata, accessible progress, and recovery actions without sending requests. */
export function UploadQueueItem({
  entry,
  busy,
  language,
  strings,
  onRetry,
  onRemove,
}: UploadQueueItemProps) {
  return (
    <li>
      <div className="file-topline">
        <span className="filename" title={entry.file.name}>
          {entry.file.name}
        </span>
        <span className="file-size">
          {new Intl.NumberFormat(language, { maximumFractionDigits: 1 }).format(
            entry.file.size / 1_000_000,
          )}{" "}
          MB
        </span>
      </div>
      <div className="file-bottomline">
        <span
          className={
            entry.status === "failed"
              ? "error"
              : entry.status === "received"
                ? "success"
                : ""
          }
          aria-live="polite"
        >
          {entry.error ? strings[entry.error] : strings[entry.status]}
          {entry.status === "uploading" && ` ${entry.progress}%`}
        </span>
        {!busy && (
          <div className="row-actions">
            {canRetry(entry) && (
              <button className="text-button" onClick={() => onRetry(entry.id)}>
                {strings.retry}
              </button>
            )}
            <button
              className="text-button"
              aria-label={`${strings.remove}: ${entry.file.name}`}
              onClick={() => onRemove(entry.id)}
            >
              {strings.remove}
            </button>
          </div>
        )}
      </div>
      {entry.status === "uploading" && (
        <progress
          max={100}
          value={entry.progress}
          aria-label={`${strings.progress}: ${entry.file.name}`}
        />
      )}
    </li>
  );
}
