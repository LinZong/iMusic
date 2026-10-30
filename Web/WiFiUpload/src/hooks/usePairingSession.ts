import { useEffect, useRef, useState } from "react";
import type { Message } from "../i18n";
import { pair } from "../services/uploadApi";
import { transferErrorMessage } from "../services/transferErrors";

/** In-memory listener authentication and page-level errors, independent of the file queue. */
interface PairingSession {
  /** Session credential retained only in memory and cleared when authorization expires. */
  token: string | undefined;
  /** Whether the current pairing request is active. */
  pairing: boolean;
  /** Localizable pairing or batch failure presented beside the pairing form. */
  error: Message | undefined;
  /** Exchanges a validated code for a credential; returns true only after successful pairing. */
  pairCode: (code: string) => Promise<boolean>;
  /** Clears a previous batch error when another upload attempt begins. */
  clearError: () => void;
  /** Reports a batch failure and invalidates the credential if the listener rejected it. */
  reportTransferError: (message: Message) => void;
}

/** Owns pairing requests and authentication expiry without persisting credentials or selected files. */
export function usePairingSession(): PairingSession {
  /** Current listener credential; never stored in cookies, URLs, or browser storage. */
  const [token, setToken] = useState<string>();
  /** Rendered pending state for the pairing form. */
  const [pairing, setPairing] = useState(false);
  /** Page-level error independent of individual file failures. */
  const [error, setError] = useState<Message>();
  /** Active request and synchronous guard against duplicate form submissions. */
  const controller = useRef<AbortController | null>(null);

  useEffect(() => () => controller.current?.abort(), []);

  /** Validates the code and ignores results from an aborted or unmounted pairing request. */
  async function pairCode(code: string): Promise<boolean> {
    if (controller.current) return false;
    if (!/^\d{6}$/.test(code)) {
      setError("invalidCode");
      return false;
    }
    const request = new AbortController();
    controller.current = request;
    setPairing(true);
    setError(undefined);
    try {
      const credential = await pair(code, request.signal);
      if (request.signal.aborted) return false;
      setToken(credential);
      return true;
    } catch (value) {
      if (!request.signal.aborted) setError(transferErrorMessage(value));
      return false;
    } finally {
      if (controller.current === request) controller.current = null;
      if (!request.signal.aborted) setPairing(false);
    }
  }

  /** Invalidates only an expired session, preserving the queue owned by the upload feature. */
  function reportTransferError(message: Message) {
    if (message === "expired") setToken(undefined);
    setError(message);
  }

  return {
    token,
    pairing,
    error,
    pairCode,
    clearError: () => setError(undefined),
    reportTransferError,
  };
}
