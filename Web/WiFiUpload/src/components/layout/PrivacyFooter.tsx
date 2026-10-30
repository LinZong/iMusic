/** Localized privacy disclosure displayed below the transfer workflow. */
interface PrivacyFooterProps {
  /** Message explaining the local-only transfer behavior. */
  message: string;
}

/** Renders the upload page's privacy disclosure without introducing external requests. */
export function PrivacyFooter({ message }: PrivacyFooterProps) {
  return (
    <footer>
      <span aria-hidden="true">⌁</span> {message}
    </footer>
  );
}
