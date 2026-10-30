import { useEffect, useState } from "react";
import { configuration } from "../services/uploadApi";
import type { Configuration } from "../domain/uploadConfiguration";

/** Native capabilities and the lifecycle of the cancellable configuration request. */
interface UploadConfiguration {
  /** Validated language and upload limits; undefined until the listener responds successfully. */
  config: Configuration | undefined;
  /** Whether the current request failed and the retry UI should be displayed. */
  failed: boolean;
  /** Starts a new request, aborting and ignoring results from the previous attempt. */
  retry: () => void;
}

/** Loads native capabilities and fences obsolete responses during retries and React remounts. */
export function useUploadConfiguration(): UploadConfiguration {
  /** Latest accepted listener configuration. */
  const [config, setConfig] = useState<Configuration>();
  /** Failure state of the current configuration request. */
  const [failed, setFailed] = useState(false);
  /** Request generation incremented by explicit retry. */
  const [generation, setGeneration] = useState(0);

  useEffect(() => {
    const request = new AbortController();
    setFailed(false);
    configuration(request.signal)
      .then((value) => {
        if (!request.signal.aborted) setConfig(value);
      })
      .catch(() => {
        if (!request.signal.aborted) setFailed(true);
      });
    return () => request.abort();
  }, [generation]);

  return { config, failed, retry: () => setGeneration((value) => value + 1) };
}
