import { PageHeader } from "./components/layout/PageHeader";
import { PrivacyFooter } from "./components/layout/PrivacyFooter";
import { PairingCard } from "./components/pairing/PairingCard";
import { UploadPanel } from "./components/upload/UploadPanel";
import { usePageLocale } from "./hooks/usePageLocale";
import { usePairingSession } from "./hooks/usePairingSession";
import { useUploadConfiguration } from "./hooks/useUploadConfiguration";

/** Composes feature boundaries and shares only native capabilities, locale, and pairing state. */
export default function App() {
  const configuration = useUploadConfiguration();
  const session = usePairingSession();
  const { language, strings } = usePageLocale(configuration.config?.language);
  return (
    <main className="shell">
      <PageHeader strings={strings} />
      <PairingCard
        strings={strings}
        configured={!!configuration.config}
        configurationFailed={configuration.failed}
        paired={!!session.token}
        pairing={session.pairing}
        error={session.error}
        onRetryConfiguration={configuration.retry}
        onPair={session.pairCode}
      />
      <UploadPanel
        config={configuration.config}
        token={session.token}
        language={language}
        strings={strings}
        onStart={session.clearError}
        onFailure={session.reportTransferError}
      />
      <PrivacyFooter message={strings.privacy} />
    </main>
  );
}
