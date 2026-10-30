import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  configuration,
  pair,
  upload,
  TransferError,
  type Configuration,
} from "./api";
import { languageFor, translations, type Language, type Message } from "./i18n";

type Status = "waiting" | "uploading" | "received" | "failed" | "cancelled";
interface Entry {
  id: number;
  file: File;
  status: Status;
  progress: number;
  error?: Message;
  invalid?: boolean;
}
const errorID = (error: unknown): Message =>
  error instanceof TransferError ? error.messageID : "networkError";
export default function App() {
  const [language, setLanguage] = useState<Language>(() =>
    languageFor(navigator.languages),
  );
  const t = translations[language];
  const [config, setConfig] = useState<Configuration>();
  const [configFailed, setConfigFailed] = useState(false);
  const [reload, setReload] = useState(0);
  const [code, setCode] = useState("");
  const [token, setToken] = useState<string>();
  const [pairing, setPairing] = useState(false);
  const [error, setError] = useState<Message>();
  const [entries, setEntries] = useState<Entry[]>([]);
  const [busy, setBusy] = useState(false);
  const [dragging, setDragging] = useState(false);
  const counter = useRef(0),
    running = useRef(false),
    controller = useRef<AbortController | null>(null);
  const pairingController = useRef<AbortController | null>(null);
  useEffect(() => {
    const request = new AbortController();
    setConfigFailed(false);
    configuration(request.signal)
      .then((value) => {
        setConfig(value);
        setLanguage(value.language);
      })
      .catch(() => {
        if (!request.signal.aborted) setConfigFailed(true);
      });
    return () => request.abort();
  }, [reload]);
  useEffect(() => {
    document.documentElement.lang = language;
    document.title = `${t.title} · iMusic`;
  }, [language, t.title]);
  useEffect(
    () => () => {
      controller.current?.abort();
      pairingController.current?.abort();
    },
    [],
  );

  async function submitPair(event: FormEvent) {
    event.preventDefault();
    if (!/^\d{6}$/.test(code)) {
      setError("invalidCode");
      return;
    }
    setPairing(true);
    setError(undefined);
    const request = new AbortController();
    pairingController.current = request;
    try {
      setToken(await pair(code, request.signal));
      setCode("");
    } catch (value) {
      if (!request.signal.aborted) setError(errorID(value));
    } finally {
      setPairing(false);
    }
  }
  function addFiles(files: File[]) {
    if (!config || busy || !token) return;
    setEntries((previous) => [
      ...previous,
      ...files.map((file) => {
        const extension = file.name.includes(".")
          ? file.name.split(".").at(-1)!.toLowerCase()
          : "";
        const error: Message | undefined = !config.extensions.includes(
          extension,
        )
          ? "unsupported"
          : file.size > config.maxFileSize
            ? "tooLarge"
            : undefined;
        return {
          id: ++counter.current,
          file,
          status: error ? ("failed" as const) : ("waiting" as const),
          progress: 0,
          error,
          invalid: !!error,
        };
      }),
    ]);
  }
  function update(id: number, changes: Partial<Entry>) {
    setEntries((previous) =>
      previous.map((entry) =>
        entry.id === id ? { ...entry, ...changes } : entry,
      ),
    );
  }
  async function startUpload() {
    if (!token || running.current) return;
    running.current = true;
    setBusy(true);
    setError(undefined);
    const request = new AbortController();
    controller.current = request;
    const pending = entries.filter((entry) => entry.status === "waiting");
    try {
      for (let index = 0; index < pending.length; index++) {
        const entry = pending[index];
        if (request.signal.aborted) {
          update(entry.id, { status: "cancelled" });
          continue;
        }
        update(entry.id, {
          status: "uploading",
          progress: 0,
          error: undefined,
        });
        try {
          await upload(entry.file, token, request.signal, (value) =>
            update(entry.id, { progress: value }),
          );
          update(entry.id, { status: "received", progress: 100 });
        } catch (value) {
          const message = errorID(value);
          update(entry.id, {
            status: message === "cancelled" ? "cancelled" : "failed",
            error: message,
          });
          if (message === "expired") {
            setToken(undefined);
            setError("expired");
            break;
          }
          if (message === "networkError") {
            setError(message);
            break;
          }
        }
      }
    } finally {
      running.current = false;
      setBusy(false);
      controller.current = null;
    }
  }
  return (
    <main className="shell">
      <header className="brand">
        <span className="brand-mark" aria-hidden="true">
          ♫
        </span>
        <span>iMusic</span>
        <span className="local-badge">Wi-Fi</span>
      </header>
      <section className="intro">
        <p className="eyebrow">{t.title}</p>
        <h1>{t.heading}</h1>
        <p>{t.instructions}</p>
      </section>
      <section className="card pairing-card" aria-labelledby="pairing-title">
        <div className="section-heading">
          <span className="step" aria-hidden="true">
            01
          </span>
          <h2 id="pairing-title">{token ? t.paired : t.pair}</h2>
          <span
            className={`connection ${token ? "connected" : ""}`}
            aria-hidden="true"
          />
        </div>
        {configFailed ? (
          <div role="alert">
            <p>{t.networkError}</p>
            <button onClick={() => setReload((value) => value + 1)}>
              {t.retry}
            </button>
          </div>
        ) : token ? (
          <p className="paired-message">✓ {t.paired}</p>
        ) : (
          <form onSubmit={submitPair}>
            <label htmlFor="code">{t.code}</label>
            <div className="pair-controls">
              <input
                id="code"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                value={code}
                placeholder="000000"
                required
                disabled={pairing || !config}
                onChange={(event) =>
                  setCode(event.target.value.replace(/\D/g, ""))
                }
                aria-describedby={error ? "error" : undefined}
              />
              <button disabled={pairing || !config} type="submit">
                {pairing ? t.pairing : t.pair}
              </button>
            </div>
          </form>
        )}
        {error && (
          <p className="error" id="error" role="alert">
            {t[error]}
          </p>
        )}
      </section>
      <section className="card" aria-labelledby="upload-title">
        <div className="section-heading">
          <span className="step" aria-hidden="true">
            02
          </span>
          <h2 id="upload-title">{t.send}</h2>
        </div>
        <label
          className={`dropzone ${dragging ? "dragging" : ""} ${!token ? "disabled" : ""}`}
          onDragOver={(event) => {
            event.preventDefault();
            if (token && !busy) setDragging(true);
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={(event) => {
            event.preventDefault();
            setDragging(false);
            addFiles(Array.from(event.dataTransfer.files));
          }}
        >
          <span className="upload-symbol" aria-hidden="true">
            ↑
          </span>
          <strong>{t.choose}</strong>
          <span>{t.drop}</span>
          <input
            type="file"
            multiple
            accept={config?.extensions
              .map((extension) => `.${extension}`)
              .join(",")}
            disabled={!token || busy}
            aria-label={t.choose}
            onChange={(event) => {
              addFiles(Array.from(event.target.files ?? []));
              event.target.value = "";
            }}
          />
        </label>
        {config && (
          <p className="formats">
            {config.extensions.join(" · ").toUpperCase()}
          </p>
        )}
        {entries.length > 0 && (
          <ul className="file-list" aria-label={t.send}>
            {entries.map((entry) => (
              <li key={entry.id}>
                <div className="file-topline">
                  <span className="filename" title={entry.file.name}>
                    {entry.file.name}
                  </span>
                  <span className="file-size">
                    {new Intl.NumberFormat(language, {
                      maximumFractionDigits: 1,
                    }).format(entry.file.size / 1_000_000)}{" "}
                    MB
                  </span>
                </div>
                <div className="file-bottomline">
                  <span
                    className={
                      entry.status === "failed"
                        ? "error"
                        : entry.status === "received"
                          ? "success"
                          : ""
                    }
                    aria-live="polite"
                  >
                    {entry.error ? t[entry.error] : t[entry.status]}
                    {entry.status === "uploading" && ` ${entry.progress}%`}
                  </span>
                  {!busy && (
                    <div className="row-actions">
                      {!entry.invalid &&
                        ["failed", "cancelled"].includes(entry.status) && (
                          <button
                            className="text-button"
                            onClick={() =>
                              update(entry.id, {
                                status: "waiting",
                                progress: 0,
                                error: undefined,
                              })
                            }
                          >
                            {t.retry}
                          </button>
                        )}
                      <button
                        className="text-button"
                        aria-label={`${t.remove}: ${entry.file.name}`}
                        onClick={() =>
                          setEntries((previous) =>
                            previous.filter((value) => value.id !== entry.id),
                          )
                        }
                      >
                        {t.remove}
                      </button>
                    </div>
                  )}
                </div>
                {entry.status === "uploading" && (
                  <progress
                    max={100}
                    value={entry.progress}
                    aria-label={`${t.progress}: ${entry.file.name}`}
                  />
                )}
              </li>
            ))}
          </ul>
        )}
        <div className="transfer-actions">
          {busy ? (
            <button
              className="secondary"
              onClick={() => controller.current?.abort()}
            >
              {t.cancel}
            </button>
          ) : (
            <button
              disabled={
                !token || !entries.some((entry) => entry.status === "waiting")
              }
              onClick={startUpload}
            >
              {t.send}
            </button>
          )}
        </div>
        <p className="hint">{t.results}</p>
      </section>
      <footer>
        <span aria-hidden="true">⌁</span> {t.privacy}
      </footer>
    </main>
  );
}
