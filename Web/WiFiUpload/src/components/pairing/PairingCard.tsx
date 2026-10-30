import { useId } from "react";
import type { Message, Strings } from "../../i18n";
import { SectionHeading } from "../shared/SectionHeading";
import { PairingForm } from "./PairingForm";

/** Authentication and configuration state rendered by the first workflow step. */
interface PairingCardProps {
  /** Localized content shared with the rest of the page. */
  strings: Strings;
  /** Whether a valid native configuration has been received. */
  configured: boolean;
  /** Whether configuration loading failed and should expose retry. */
  configurationFailed: boolean;
  /** Whether the session currently has an accepted listener credential. */
  paired: boolean;
  /** Whether an authentication request is pending. */
  pairing: boolean;
  /** Optional page-level pairing or transfer failure. */
  error?: Message;
  /** Retries native capability loading. */
  onRetryConfiguration: () => void;
  /** Requests pairing without exposing the credential to this presentational component. */
  onPair: (code: string) => Promise<boolean>;
}

/** Presents configuration recovery, pairing, connection status, and session-level failures. */
export function PairingCard({
  strings,
  configured,
  configurationFailed,
  paired,
  pairing,
  error,
  onRetryConfiguration,
  onPair,
}: PairingCardProps) {
  /** Unique target for the pairing field's accessible error description. */
  const errorId = useId();
  return (
    <section className="card pairing-card" aria-labelledby="pairing-title">
      <SectionHeading
        id="pairing-title"
        step="01"
        title={paired ? strings.paired : strings.pair}
      >
        <span
          className={`connection ${paired ? "connected" : ""}`}
          aria-hidden="true"
        />
      </SectionHeading>
      {configurationFailed ? (
        <div role="alert">
          <p>{strings.networkError}</p>
          <button onClick={onRetryConfiguration}>{strings.retry}</button>
        </div>
      ) : paired ? (
        <p className="paired-message">✓ {strings.paired}</p>
      ) : (
        <PairingForm
          strings={strings}
          disabled={pairing || !configured}
          pairing={pairing}
          errorId={error ? errorId : undefined}
          onPair={onPair}
        />
      )}
      {error && (
        <p className="error" id={errorId} role="alert">
          {strings[error]}
        </p>
      )}
    </section>
  );
}
