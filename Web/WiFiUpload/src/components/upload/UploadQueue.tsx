import type { UploadEntry } from "../../domain/uploadQueue";
import type { Language, Strings } from "../../i18n";
import { UploadQueueItem } from "./UploadQueueItem";

/** Ordered queue presentation and occurrence-specific callbacks. */
interface UploadQueueProps {
  /** Queue snapshot; repeated file selections have distinct identities. */
  entries: readonly UploadEntry[];
  /** Whether the current batch prevents row edits. */
  busy: boolean;
  /** Locale used by each file-size label. */
  language: Language;
  /** Localized queue and row labels. */
  strings: Strings;
  /** Requests retry of one recoverable occurrence. */
  onRetry: (id: number) => void;
  /** Requests removal of one occurrence. */
  onRemove: (id: number) => void;
}

/** Preserves stable occurrence keys and delegates individual row rendering. */
export function UploadQueue({ entries, ...rowProps }: UploadQueueProps) {
  if (!entries.length) return null;
  return (
    <ul className="file-list" aria-label={rowProps.strings.send}>
      {entries.map((entry) => (
        <UploadQueueItem key={entry.id} entry={entry} {...rowProps} />
      ))}
    </ul>
  );
}
