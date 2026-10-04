import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, checksum] = process.argv.slice(2);
if (!url) {
  execFileSync("apt-get", ["update"], { stdio: "inherit" });
  execFileSync("apt-get", ["install", "-y", "--no-install-recommends", "ffmpeg"], { stdio: "inherit" });
} else {
  const source = new URL(url);
  if (
    source.protocol !== "https:" ||
    source.username ||
    source.password ||
    !/^[a-f0-9]{64}$/.test(checksum ?? "")
  )
    throw Error("Exact HTTPS runtime input URL and SHA256 are required");
  const directory = mkdtempSync(join(tmpdir(), "leafwake-runtime-"));
  try {
    const response = await fetch(source, { signal: AbortSignal.timeout(180000) });
    if (!response.ok) throw Error(`Runtime inputs: ${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (createHash("sha256").update(bytes).digest("hex") !== checksum)
      throw Error("Runtime input checksum mismatch");
    const archive = join(directory, "inputs.tar.gz");
    writeFileSync(archive, bytes);
    execFileSync("tar", ["-xzf", archive, "-C", directory]);
    const packages = readdirSync(join(directory, "debs"))
      .filter((name) => name.endsWith(".deb"))
      .sort();
    if (!packages.length) throw Error("No runtime package inputs");
    execFileSync("dpkg", ["-i", ...packages.map((name) => join(directory, "debs", name))], {
      stdio: "inherit",
    });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
rmSync("/var/lib/apt/lists", { recursive: true, force: true });
