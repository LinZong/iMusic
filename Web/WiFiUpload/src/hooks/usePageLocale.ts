import { useEffect, useState } from "react";
import {
  languageFor,
  translations,
  type Language,
  type Strings,
} from "../i18n";

/** Language and complete message table shared by the page's presentational components. */
interface PageLocale {
  /** Native app language when available, otherwise the initial browser language. */
  language: Language;
  /** Bundled messages selected by the active language. */
  strings: Strings;
}

/** Resolves page language and synchronizes document metadata without owning upload state. */
export function usePageLocale(appLanguage?: Language): PageLocale {
  /** Stable browser fallback used before the native configuration is available. */
  const [browserLanguage] = useState(() => languageFor(navigator.languages));
  const language = appLanguage ?? browserLanguage;
  const strings = translations[language];

  useEffect(() => {
    document.documentElement.lang = language;
    document.title = `${strings.title} · iMusic`;
  }, [language, strings.title]);

  return { language, strings };
}
