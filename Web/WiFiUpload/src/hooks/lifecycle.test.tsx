import { act, renderHook, waitFor } from "@testing-library/react";
import { StrictMode } from "react";
import { beforeEach, expect, it, vi } from "vitest";
import * as api from "../services/uploadApi";
import type { Configuration } from "../domain/uploadConfiguration";
import { useUploadConfiguration } from "./useUploadConfiguration";
import { usePairingSession } from "./usePairingSession";
import { useUploadQueue } from "./useUploadQueue";

vi.mock("../services/uploadApi", async (importOriginal) => ({
  ...(await importOriginal<typeof api>()),
  configuration: vi.fn(),
  pair: vi.fn(),
  upload: vi.fn(),
}));
const config: Configuration = {
  language: "en",
  extensions: ["wav"],
  maxFileSize: 1000,
};

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(api.configuration).mockResolvedValue(config);
  vi.mocked(api.pair).mockResolvedValue("token");
  vi.mocked(api.upload).mockResolvedValue();
});

it("ignores obsolete configuration responses during StrictMode effect replay", async () => {
  let obsolete!: (value: Configuration) => void;
  vi.mocked(api.configuration).mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        obsolete = resolve;
      }),
  );
  const { result } = renderHook(useUploadConfiguration, {
    wrapper: StrictMode,
  });
  await waitFor(() => expect(result.current.config?.language).toBe("en"));
  expect(vi.mocked(api.configuration).mock.calls[0][0].aborted).toBe(true);
  await act(async () => {
    obsolete({ ...config, language: "zh-Hant" });
  });
  expect(result.current.config?.language).toBe("en");
});

it("guards duplicate pairing requests and aborts authentication on unmount", async () => {
  let complete!: (value: string) => void;
  vi.mocked(api.pair).mockImplementation(
    () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  );
  const { result, unmount } = renderHook(usePairingSession);
  let pending!: Promise<boolean>;
  let duplicate!: Promise<boolean>;
  act(() => {
    pending = result.current.pairCode("123456");
    duplicate = result.current.pairCode("123456");
  });
  expect(api.pair).toHaveBeenCalledTimes(1);
  await expect(duplicate).resolves.toBe(false);
  unmount();
  expect(vi.mocked(api.pair).mock.calls[0][1].aborted).toBe(true);
  complete("obsolete-token");
  await expect(pending).resolves.toBe(false);
});

it("serializes a batch and blocks edits or duplicate starts before the next render", async () => {
  const complete: (() => void)[] = [];
  vi.mocked(api.upload).mockImplementation(
    () =>
      new Promise((resolve) => {
        complete.push(resolve);
      }),
  );
  const onStart = vi.fn(),
    onFailure = vi.fn();
  const { result } = renderHook(() =>
    useUploadQueue(config, "token", onStart, onFailure),
  );
  act(() =>
    result.current.addFiles([
      new File(["one"], "one.wav"),
      new File(["two"], "two.wav"),
    ]),
  );
  let pending!: Promise<void>;
  act(() => {
    pending = result.current.startUpload();
    void result.current.startUpload();
    result.current.removeEntry(result.current.entries[0].id);
    result.current.addFiles([new File(["ignored"], "ignored.wav")]);
  });
  expect(api.upload).toHaveBeenCalledTimes(1);
  expect(result.current.entries).toHaveLength(2);
  await act(async () => {
    complete[0]();
  });
  expect(api.upload).toHaveBeenCalledTimes(2);
  await act(async () => {
    complete[1]();
    await pending;
  });
  expect(result.current.entries.map((entry) => entry.status)).toEqual([
    "received",
    "received",
  ]);
  expect(result.current.busy).toBe(false);
  expect(onStart).toHaveBeenCalledTimes(1);
  expect(onFailure).not.toHaveBeenCalled();
});

it("aborts an active upload on unmount without reporting a false session failure", async () => {
  vi.mocked(api.upload).mockImplementation(
    (_file, _token, signal) =>
      new Promise((_resolve, reject) => {
        signal.addEventListener(
          "abort",
          () => reject(new api.TransferError("networkError")),
          { once: true },
        );
      }),
  );
  const onFailure = vi.fn();
  const { result, unmount } = renderHook(() =>
    useUploadQueue(config, "token", vi.fn(), onFailure),
  );
  act(() => result.current.addFiles([new File(["one"], "one.wav")]));
  let pending!: Promise<void>;
  act(() => {
    pending = result.current.startUpload();
  });
  unmount();
  expect(vi.mocked(api.upload).mock.calls[0][2].aborted).toBe(true);
  await pending;
  expect(onFailure).not.toHaveBeenCalled();
});
