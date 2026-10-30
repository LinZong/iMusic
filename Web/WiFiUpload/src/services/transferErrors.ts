import type { Message } from "../i18n";
import { TransferError } from "./uploadApi";

/** Maps transport failures to shared message keys without exposing internal network details. */
export function transferErrorMessage(error: unknown): Message {
  return error instanceof TransferError ? error.messageID : "networkError";
}
