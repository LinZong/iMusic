import type messages from "./messages.json";
export type Language = "en" | "zh-Hans" | "zh-Hant";
export type Message = keyof typeof messages;
export type Strings = Record<Message, string>;
declare const __UPLOAD_TRANSLATIONS__: Record<Language, Strings>;
export const translations = __UPLOAD_TRANSLATIONS__;
export function languageFor(languages: readonly string[]): Language {
  for (const language of languages) {
    const value = language.toLowerCase().replaceAll("_", "-");
    if (value.startsWith("zh"))
      return /hant|tw|hk|mo/.test(value) ? "zh-Hant" : "zh-Hans";
    if (value.startsWith("en")) return "en";
  }
  return "en";
}
