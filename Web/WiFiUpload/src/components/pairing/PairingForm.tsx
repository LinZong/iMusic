import { useId, useState, type FormEvent } from "react";
import type { Strings } from "../../i18n";

/** Form presentation and an authentication command supplied by the session hook. */
interface PairingFormProps {
  /** Localized field and button labels. */
  strings: Strings;
  /** Whether configuration is unavailable or a request is already pending. */
  disabled: boolean;
  /** Whether to display the pairing-in-progress label. */
  pairing: boolean;
  /** Optional identifier of the associated session error. */
  errorId?: string;
  /** Authenticates the entered code; network handling belongs to the session hook. */
  onPair: (code: string) => Promise<boolean>;
}

/** Owns only the editable pairing code; credentials and requests never live in the form. */
export function PairingForm({
  strings,
  disabled,
  pairing,
  errorId,
  onPair,
}: PairingFormProps) {
  /** Six-digit input draft, discarded when successful pairing replaces this form. */
  const [code, setCode] = useState("");
  /** Unique association between the code field and its visible label. */
  const codeId = useId();

  /** Prevents browser navigation and delegates code validation and authentication. */
  function submit(event: FormEvent) {
    event.preventDefault();
    if (!disabled) void onPair(code);
  }

  return (
    <form onSubmit={submit}>
      <label htmlFor={codeId}>{strings.code}</label>
      <div className="pair-controls">
        <input
          id={codeId}
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]{6}"
          maxLength={6}
          value={code}
          placeholder="000000"
          required
          disabled={disabled}
          onChange={(event) => setCode(event.target.value.replace(/\D/g, ""))}
          aria-describedby={errorId}
        />
        <button disabled={disabled} type="submit">
          {pairing ? strings.pairing : strings.pair}
        </button>
      </div>
    </form>
  );
}
