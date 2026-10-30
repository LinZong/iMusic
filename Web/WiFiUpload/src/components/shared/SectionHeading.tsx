import type { ReactNode } from "react";

/** Accessible heading shared by the two numbered upload steps. */
interface SectionHeadingProps {
  /** Identifier referenced by the containing section's aria-labelledby attribute. */
  id: string;
  /** Decorative step number. */
  step: string;
  /** Localized section title. */
  title: string;
  /** Optional trailing status decoration. */
  children?: ReactNode;
}

/** Renders a numbered section heading without owning feature state. */
export function SectionHeading({
  id,
  step,
  title,
  children,
}: SectionHeadingProps) {
  return (
    <div className="section-heading">
      <span className="step" aria-hidden="true">
        {step}
      </span>
      <h2 id={id}>{title}</h2>
      {children}
    </div>
  );
}
