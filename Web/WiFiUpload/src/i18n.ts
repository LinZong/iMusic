import type messages from "./messages.json";
/** Language identifiers shared with the native localization catalog. */
export type Language = "en" | "zh-Hans" | "zh-Hant";
/** Valid message keys required by the browser upload page. */
export type Message = keyof typeof messages;
/** Complete localized message table for one supported language. */
export type Strings = Record<Message, string>;
/** Build-time translation tables compiled from the authoritative native string catalog. */
declare const __UPLOAD_TRANSLATIONS__: Record<Language, Strings>;
/** Shared translation tables bundled into the offline browser assets. */
export const translations = __UPLOAD_TRANSLATIONS__;
/** Chooses the first supported browser language, distinguishing Traditional Chinese regions and falling back to English. */
export function languageFor(languages: readonly string[]): Language {
  for (const language of languages) {
    const value = language.toLowerCase().replaceAll("_", "-");
    if (value.startsWith("zh"))
      return /hant|tw|hk|mo/.test(value) ? "zh-Hant" : "zh-Hans";
    if (value.startsWith("en")) return "en";
  }
  return "en";
}
