import { useUploadQueue } from "../../hooks/useUploadQueue";
import type { Language, Message, Strings } from "../../i18n";
import type { Configuration } from "../../domain/uploadConfiguration";
import { SectionHeading } from "../shared/SectionHeading";
import { FileDropzone } from "./FileDropzone";
import { UploadActions } from "./UploadActions";
import { UploadQueue } from "./UploadQueue";

/** Shared capabilities and session boundary injected into the upload feature. */
interface UploadPanelProps {
  /** Validated native upload limits, absent before configuration succeeds. */
  config: Configuration | undefined;
  /** In-memory credential consumed only by the upload workflow. */
  token: string | undefined;
  /** Locale for file-size formatting. */
  language: Language;
  /** Localized upload interface text. */
  strings: Strings;
  /** Clears a previous session-level failure at the beginning of a batch. */
  onStart: () => void;
  /** Reports a stopping network or authorization failure to the session owner. */
  onFailure: (message: Message) => void;
}

/** Composes the upload feature and retains its queue across authentication expiry and re-pairing. */
export function UploadPanel({
  config,
  token,
  language,
  strings,
  onStart,
  onFailure,
}: UploadPanelProps) {
  const queue = useUploadQueue(config, token, onStart, onFailure);
  const ready = !!config && !!token;
  return (
    <section className="card" aria-labelledby="upload-title">
      <SectionHeading id="upload-title" step="02" title={strings.send} />
      <FileDropzone
        strings={strings}
        disabled={!ready || queue.busy}
        extensions={config?.extensions ?? []}
        onFiles={queue.addFiles}
      />
      {config && (
        <p className="formats">{config.extensions.join(" · ").toUpperCase()}</p>
      )}
      <UploadQueue
        entries={queue.entries}
        busy={queue.busy}
        language={language}
        strings={strings}
        onRetry={queue.retryEntry}
        onRemove={queue.removeEntry}
      />
      <UploadActions
        strings={strings}
        busy={queue.busy}
        canStart={
          ready && queue.entries.some((entry) => entry.status === "waiting")
        }
        onStart={queue.startUpload}
        onCancel={queue.cancelUpload}
      />
      <p className="hint">{strings.results}</p>
    </section>
  );
}
