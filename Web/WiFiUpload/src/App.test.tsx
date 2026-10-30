import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import * as api from "./api";
import { languageFor, translations } from "./i18n";
vi.mock("./api", async (importOriginal) => ({
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
  vi.mocked(api.configuration).mockResolvedValue(config);
  vi.mocked(api.pair).mockResolvedValue("session-token");
  vi.mocked(api.upload).mockResolvedValue();
});
async function paired() {
  const user = userEvent.setup();
  render(<App />);
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
