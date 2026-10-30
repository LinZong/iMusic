// Build into SwiftPM's plugin directory, never mutate package sources in a sandbox.
import { createHash } from "node:crypto";
import { readdir, readFile, mkdir, writeFile, rename } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = dirname(fileURLToPath(import.meta.url));
const work = process.argv[2];
if (!work) throw new Error("Usage: node build.mjs <plugin-work-directory>");
const resources = join(work, "Resources");
async function files(directory) {
  const result = [];
  for (const entry of (await readdir(directory, { withFileTypes: true })).sort(
    (a, b) => a.name.localeCompare(b.name),
  )) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) result.push(...(await files(path)));
    else result.push(path);
  }
  return result;
}
const inputs = [
  join(root, "package.json"),
  join(root, "package-lock.json"),
  join(root, "tsconfig.json"),
  join(root, "vite.config.ts"),
  join(root, "../../Localization/Strings.json"),
  join(root, "../../Scripts/build_wifi_upload.sh"),
  join(root, "index.html"),
  fileURLToPath(import.meta.url),
  ...(await files(join(root, "src"))),
];
const hash = createHash("sha256").update(process.version);
for (const path of inputs) hash.update(path).update(await readFile(path));
const fingerprint = hash.digest("hex");
try {
  const manifest = JSON.parse(
    await readFile(join(resources, "upload-assets.json"), "utf8"),
  );
  if ((await readFile(join(work, "fingerprint"), "utf8")) === fingerprint) {
    for (const name of manifest.files) await readFile(join(resources, name));
    await readFile(join(resources, "upload-licenses.txt"));
    process.exit(0);
  }
} catch {
  /* Missing or incomplete outputs must rebuild. */
}
// The lockfile must describe the installed dependencies used by this build.
const installed = JSON.parse(
  await readFile(join(root, "node_modules/.package-lock.json"), "utf8"),
);
const locked = JSON.parse(
  await readFile(join(root, "package-lock.json"), "utf8"),
);
for (const [name, entry] of Object.entries(locked.packages)) {
  if (
    name &&
    !entry.optional &&
    installed.packages[name]?.version !== entry.version
  )
    throw new Error(
      "Wi-Fi Upload dependencies are stale. Run npm ci in Web/WiFiUpload.",
    );
}
for (const [script, args] of [
  [
    "typescript/bin/tsc",
    ["--project", join(root, "tsconfig.json"), "--noEmit"],
  ],
  [
    "vite/bin/vite.js",
    [
      "build",
      root,
      "--config",
      join(root, "vite.config.ts"),
      "--configLoader",
      "runner",
      "--outDir",
      resources,
      "--emptyOutDir",
    ],
  ],
]) {
  const result = spawnSync(
    process.execPath,
    [join(root, "node_modules", script), ...args],
    { cwd: root, stdio: "inherit" },
  );
  if (result.status !== 0) process.exit(result.status ?? 1);
}
await rename(
  join(resources, "index.html"),
  join(resources, "upload-index.html"),
);
// Keep runtime dependency notices in the distributed resource bundle.
const notices = await Promise.all(
  ["react", "react-dom", "scheduler"].map(
    async (name) =>
      `${name}\n${await readFile(join(root, "node_modules", name, "LICENSE"), "utf8")}`,
  ),
);
await writeFile(join(resources, "upload-licenses.txt"), notices.join("\n\n"));
const output = (await readdir(resources))
  .filter((name) => name !== "upload-licenses.txt")
  .sort();
await writeFile(
  join(resources, "upload-assets.json"),
  JSON.stringify({ files: output }),
);
await mkdir(work, { recursive: true });
await writeFile(join(work, "fingerprint"), fingerprint);
