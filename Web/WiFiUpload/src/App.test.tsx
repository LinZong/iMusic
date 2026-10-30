import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import * as api from "./services/uploadApi";
import { languageFor, translations } from "./i18n";
import { StrictMode } from "react";
vi.mock("./services/uploadApi", async (importOriginal) => ({
  ...(await importOriginal<typeof api>()),
  configuration: vi.fn(),
  pair: vi.fn(),
  upload: vi.fn(),
}));
const config = {
  language: "en" as const,
  extensions: ["mp3", "wav"],
  maxFileSize: 1000,
};
beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(api.configuration).mockResolvedValue(config);
  vi.mocked(api.pair).mockResolvedValue("session-token");
  vi.mocked(api.upload).mockResolvedValue();
});
async function paired(strict = false) {
  const user = userEvent.setup();
  render(
    strict ? (
      <StrictMode>
        <App />
      </StrictMode>
    ) : (
      <App />
    ),
  );
  await waitFor(() =>
    expect(screen.getByLabelText("Six-Digit Pairing Code")).toBeEnabled(),
  );
  await user.type(screen.getByLabelText("Six-Digit Pairing Code"), "123456");
  await user.click(screen.getByRole("button", { name: "Pair" }));
  await waitFor(() =>
    expect(screen.getByLabelText("Choose Music")).toBeEnabled(),
  );
  return user;
}
function choose(files: File[]) {
  fireEvent.change(screen.getByLabelText("Choose Music"), {
    target: { files },
  });
}
describe("Wi-Fi Upload", () => {
  it("keeps all translations complete and selects Chinese scripts and English fallback", () => {
    expect(languageFor(["zh-TW"])).toBe("zh-Hant");
    expect(languageFor(["zh-CN"])).toBe("zh-Hans");
    expect(languageFor(["fr-FR"])).toBe("en");
    for (const values of Object.values(translations))
      expect(Object.keys(values)).toEqual(Object.keys(translations.en));
  });
  it("follows the app language supplied by the server", async () => {
    vi.mocked(api.configuration).mockResolvedValue({
      ...config,
      language: "zh-Hant",
    });
    render(<App />);
    expect(
      await screen.findByLabelText(translations["zh-Hant"].code),
    ).toBeEnabled();
    expect(document.documentElement.lang).toBe("zh-Hant");
    expect(screen.getByRole("heading", { level: 1 })).toHaveTextContent(
      translations["zh-Hant"].heading,
    );
  });
  it("requires pairing and reports a rejected code", async () => {
    vi.mocked(api.pair).mockRejectedValue(new api.TransferError("wrongCode"));
    const user = userEvent.setup();
    render(<App />);
    expect(screen.getByLabelText("Choose Music")).toBeDisabled();
    await waitFor(() =>
      expect(screen.getByLabelText("Six-Digit Pairing Code")).toBeEnabled(),
    );
    await user.type(screen.getByLabelText("Six-Digit Pairing Code"), "654321");
    await user.click(screen.getByRole("button", { name: "Pair" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      translations.en.wrongCode,
    );
    expect(screen.getByLabelText("Choose Music")).toBeDisabled();
  });
  it("validates files, preserves Unicode names, and only marks received after acceptance", async () => {
    const user = await paired();
    let complete!: () => void;
    vi.mocked(api.upload).mockImplementation(
      (_file, _token, _signal, progress) => {
        progress(42);
        return new Promise((resolve) => {
          complete = resolve;
        });
      },
    );
    const song = new File(["audio"], "音楽 🎵.MP3");
    choose([
      song,
      new File(["bad"], "bad.exe"),
      new File(["a".repeat(1001)], "large.wav"),
    ]);
    expect(screen.getByText(translations.en.unsupported)).toBeVisible();
    expect(screen.getByText(translations.en.tooLarge)).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(screen.getByRole("progressbar")).toHaveAttribute("value", "42");
    expect(
      screen.queryByText("Received", { exact: true }),
    ).not.toBeInTheDocument();
    expect(api.upload).toHaveBeenCalledWith(
      song,
      "session-token",
      expect.any(AbortSignal),
      expect.any(Function),
    );
    complete();
    expect(await screen.findByText("Received", { exact: true })).toBeVisible();
    expect(api.upload).toHaveBeenCalledTimes(1);
  });
  it("cancels the active request and queued files, then allows retry", async () => {
    const user = await paired();
    vi.mocked(api.upload).mockImplementation(
      (_file, _token, signal) =>
        new Promise((_resolve, reject) => {
          signal.addEventListener(
            "abort",
            () => reject(new api.TransferError("cancelled")),
            { once: true },
          );
        }),
    );
    choose([new File(["one"], "one.wav"), new File(["two"], "two.wav")]);
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    await user.click(screen.getByRole("button", { name: "Cancel" }));
    expect(
      await screen.findAllByText("Cancelled", { exact: true }),
    ).toHaveLength(2);
    expect(api.upload).toHaveBeenCalledTimes(1);
    await user.click(screen.getAllByRole("button", { name: "Try Again" })[0]);
    vi.mocked(api.upload).mockResolvedValue();
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(await screen.findByText("Received", { exact: true })).toBeVisible();
  });
  it("stops on expired authorization and requires re-pairing without losing queued files", async () => {
    const user = await paired();
    vi.mocked(api.upload).mockRejectedValue(new api.TransferError("expired"));
    choose([new File(["one"], "one.wav"), new File(["two"], "two.wav")]);
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      translations.en.expired,
    );
    expect(screen.getByLabelText("Choose Music")).toBeDisabled();
    expect(screen.getByText("two.wav")).toBeVisible();
    expect(api.upload).toHaveBeenCalledTimes(1);
  });
});

describe("composed upload features", () => {
  it("recovers a failed configuration request before enabling pairing", async () => {
    vi.mocked(api.configuration).mockRejectedValueOnce(new Error("offline"));
    const user = userEvent.setup();
    render(<App />);
    expect(await screen.findByRole("alert")).toHaveTextContent(
      translations.en.networkError,
    );
    expect(screen.getByLabelText("Choose Music")).toBeDisabled();
    await user.click(screen.getByRole("button", { name: "Try Again" }));
    expect(
      await screen.findByLabelText("Six-Digit Pairing Code"),
    ).toBeEnabled();
    expect(api.configuration).toHaveBeenCalledTimes(2);
  });

  it("keeps waiting entries after a network failure and can continue without pairing again", async () => {
    const user = await paired();
    vi.mocked(api.upload).mockRejectedValueOnce(
      new api.TransferError("networkError"),
    );
    choose([new File(["one"], "one.wav"), new File(["two"], "two.wav")]);
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      translations.en.networkError,
    );
    expect(api.upload).toHaveBeenCalledTimes(1);
    expect(screen.getByText("Waiting", { exact: true })).toBeVisible();
    expect(screen.getByLabelText("Choose Music")).toBeEnabled();
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(await screen.findByText("Received", { exact: true })).toBeVisible();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Try Again" }));
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(
      await screen.findAllByText("Received", { exact: true }),
    ).toHaveLength(2);
    expect(api.pair).toHaveBeenCalledTimes(1);
  });

  it("retains the queue through re-pairing and retries with the new credential", async () => {
    const user = await paired();
    vi.mocked(api.upload).mockRejectedValueOnce(
      new api.TransferError("expired"),
    );
    choose([new File(["one"], "one.wav"), new File(["two"], "two.wav")]);
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      translations.en.expired,
    );
    const code = screen.getByLabelText("Six-Digit Pairing Code");
    expect(code).toHaveValue("");
    vi.mocked(api.pair).mockResolvedValue("renewed-token");
    await user.type(code, "654321");
    await user.click(screen.getByRole("button", { name: "Pair" }));
    await waitFor(() =>
      expect(screen.getByLabelText("Choose Music")).toBeEnabled(),
    );
    expect(screen.getByText("one.wav")).toBeVisible();
    expect(screen.getByText("two.wav")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Try Again" }));
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(
      await screen.findAllByText("Received", { exact: true }),
    ).toHaveLength(2);
    expect(api.upload).toHaveBeenCalledTimes(3);
    expect(
      vi
        .mocked(api.upload)
        .mock.calls.slice(1)
        .map((call) => call[1]),
    ).toEqual(["renewed-token", "renewed-token"]);
  });

  it("keeps repeated file selections distinct under StrictMode and removes only one occurrence", async () => {
    const user = await paired(true);
    const file = new File(["same"], "same.wav");
    choose([file]);
    choose([file]);
    expect(screen.getAllByText("same.wav")).toHaveLength(2);
    await user.click(
      screen.getAllByRole("button", { name: "Remove: same.wav" })[0],
    );
    expect(screen.getAllByText("same.wav")).toHaveLength(1);
    await user.click(screen.getByRole("button", { name: "Upload Music" }));
    expect(await screen.findByText("Received", { exact: true })).toBeVisible();
    expect(api.upload).toHaveBeenCalledTimes(1);
  });

  it("ignores dragged files while pairing is unavailable", async () => {
    render(<App />);
    const picker = screen.getByLabelText("Choose Music");
    const dropzone = picker.closest("label")!;
    fireEvent.dragOver(dropzone);
    fireEvent.drop(dropzone, {
      dataTransfer: { files: [new File(["song"], "ignored.wav")] },
    });
    expect(dropzone).not.toHaveClass("dragging");
    expect(screen.queryByText("ignored.wav")).not.toBeInTheDocument();
    expect(picker).toBeDisabled();
  });
});
