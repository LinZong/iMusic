import type { Language } from "../i18n";

/** Runtime upload capabilities advertised by the native app for this listener session. */
export interface Configuration {
  /** App-selected language, which takes priority over the browser language. */
  language: Language;
  /** Lowercase audio extensions the native importer accepts. */
  extensions: string[];
  /** Maximum allowed size of one uploaded file, in bytes. */
  maxFileSize: number;
}
