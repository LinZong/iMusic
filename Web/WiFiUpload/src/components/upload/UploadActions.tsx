import type { Strings } from "../../i18n";

/** Batch-level controls without queue or request ownership. */
interface UploadActionsProps {
  /** Localized send and cancel button labels. */
  strings: Strings;
  /** Whether a batch is active and cancellation should be offered. */
  busy: boolean;
  /** Whether at least one waiting file and a valid session are available. */
  canStart: boolean;
  /** Begins the sequential upload workflow. */
  onStart: () => Promise<void>;
  /** Cancels the active workflow. */
  onCancel: () => void;
}

/** Switches between sending and cancellation while keeping transport logic in the queue hook. */
export function UploadActions({
  strings,
  busy,
  canStart,
  onStart,
  onCancel,
}: UploadActionsProps) {
  return (
    <div className="transfer-actions">
      {busy ? (
        <button className="secondary" onClick={onCancel}>
          {strings.cancel}
        </button>
      ) : (
        <button disabled={!canStart} onClick={() => void onStart()}>
          {strings.send}
        </button>
      )}
    </div>
  );
}
