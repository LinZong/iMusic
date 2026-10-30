import type { Strings } from "../../i18n";

/** Localized content for the page's branding and introduction. */
interface PageHeaderProps {
  /** Complete message table selected by the native app language. */
  strings: Strings;
}

/** Renders static branding and localized upload instructions. */
export function PageHeader({ strings }: PageHeaderProps) {
  return (
    <>
      <header className="brand">
        <span className="brand-mark" aria-hidden="true">
          ♫
        </span>
        <span>iMusic</span>
        <span className="local-badge">Wi-Fi</span>
      </header>
      <section className="intro">
        <p className="eyebrow">{strings.title}</p>
        <h1>{strings.heading}</h1>
        <p>{strings.instructions}</p>
      </section>
    </>
  );
}
