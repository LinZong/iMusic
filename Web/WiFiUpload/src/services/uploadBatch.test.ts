import { expect, it, vi } from "vitest";
import { createUploadEntry } from "../domain/uploadQueue";
import { TransferError } from "./uploadApi";
import { runUploadBatch, type UploadTransport } from "./uploadBatch";

/** Creates distinct occurrences without depending on React or a browser transport. */
function entries() {
  return [1, 2, 3].map((id) =>
    createUploadEntry(id, new File(["silent"], `${id}.wav`), {
      language: "en",
      extensions: ["wav"],
      maxFileSize: 1000,
    }),
  );
}

it("runs transport sequentially and publishes progress for each occurrence", async () => {
  const order: string[] = [];
  const transport: UploadTransport = vi.fn(
    async (file, _token, _signal, progress) => {
      order.push(`start:${file.name}`);
      progress(50);
      await Promise.resolve();
      order.push(`end:${file.name}`);
    },
  );
  const update = vi.fn();
  const failure = vi.fn();
  await runUploadBatch({
    pending: entries(),
    token: "captured-token",
    signal: new AbortController().signal,
    transport,
    update,
    onFailure: failure,
  });
  expect(order).toEqual([
    "start:1.wav",
    "end:1.wav",
    "start:2.wav",
    "end:2.wav",
    "start:3.wav",
    "end:3.wav",
  ]);
  expect(update).toHaveBeenCalledWith(2, { progress: 50 });
  expect(update).toHaveBeenCalledWith(3, { status: "received", progress: 100 });
  expect(failure).not.toHaveBeenCalled();
});

it("stops on expired credentials and leaves unsent occurrences unchanged", async () => {
  const transport = vi.fn().mockRejectedValue(new TransferError("expired"));
  const update = vi.fn();
  const failure = vi.fn();
  await runUploadBatch({
    pending: entries(),
    token: "expired",
    signal: new AbortController().signal,
    transport,
    update,
    onFailure: failure,
  });
  expect(transport).toHaveBeenCalledTimes(1);
  expect(update).toHaveBeenCalledWith(1, {
    status: "failed",
    error: "expired",
  });
  expect(update.mock.calls.every(([id]) => id === 1)).toBe(true);
  expect(failure).toHaveBeenCalledWith("expired");
});

it("cancels the active occurrence and all remaining entries without sending them", async () => {
  const controller = new AbortController();
  const transport = vi.fn(async () => {
    controller.abort();
    throw new TransferError("cancelled");
  });
  const update = vi.fn();
  const failure = vi.fn();
  await runUploadBatch({
    pending: entries(),
    token: "token",
    signal: controller.signal,
    transport,
    update,
    onFailure: failure,
  });
  expect(transport).toHaveBeenCalledTimes(1);
  expect(update).toHaveBeenCalledWith(1, {
    status: "cancelled",
    error: "cancelled",
  });
  expect(update).toHaveBeenCalledWith(2, { status: "cancelled" });
  expect(update).toHaveBeenCalledWith(3, { status: "cancelled" });
  expect(failure).not.toHaveBeenCalled();
});
