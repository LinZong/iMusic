import { beforeEach, expect, it, vi } from "vitest";
import { upload } from "./uploadApi";
class MockXHR {
  static last: MockXHR;
  upload = {
    onprogress: null as
      | null
      | ((event: {
          lengthComputable: boolean;
          loaded: number;
          total: number;
        }) => void),
  };
  status = 0;
  timeout = 0;
  onload?: () => void;
  onerror?: () => void;
  onabort?: () => void;
  ontimeout?: () => void;
  open = vi.fn();
  setRequestHeader = vi.fn();
  send = vi.fn();
  abort = vi.fn(() => this.onabort?.());
  constructor() {
    MockXHR.last = this;
  }
}
beforeEach(() => {
  vi.stubGlobal("XMLHttpRequest", MockXHR);
});
it("encodes the filename, uses a raw file body, and reserves 100% for HTTP 202", async () => {
  const file = new File(["data"], "音楽 &?#.wav"),
    progress = vi.fn();
  const promise = upload(
      file,
      "secret",
      new AbortController().signal,
      progress,
    ),
    xhr = MockXHR.last;
  expect(xhr.open).toHaveBeenCalledWith(
    "POST",
    `/upload?${new URLSearchParams({ name: file.name })}`,
  );
  expect(xhr.setRequestHeader).toHaveBeenCalledWith(
    "Authorization",
    "Bearer secret",
  );
  expect(xhr.send).toHaveBeenCalledWith(file);
  xhr.upload.onprogress?.({ lengthComputable: true, loaded: 4, total: 4 });
  expect(progress).toHaveBeenCalledWith(99);
  xhr.status = 202;
  xhr.onload?.();
  await expect(promise).resolves.toBeUndefined();
});
it.each([
  [401, "expired"],
  [413, "tooLarge"],
  [400, "unsupported"],
  [500, "failed"],
])("maps HTTP %s to a localizable error", async (status, messageID) => {
  const promise = upload(
    new File(["data"], "song.wav"),
    "secret",
    new AbortController().signal,
    vi.fn(),
  );
  MockXHR.last.status = status as number;
  MockXHR.last.onload?.();
  await expect(promise).rejects.toMatchObject({ messageID });
});
it("aborts the network request on cancellation", async () => {
  const controller = new AbortController();
  const promise = upload(
    new File(["data"], "song.wav"),
    "secret",
    controller.signal,
    vi.fn(),
  );
  controller.abort();
  expect(MockXHR.last.abort).toHaveBeenCalledOnce();
  await expect(promise).rejects.toMatchObject({ messageID: "cancelled" });
});
