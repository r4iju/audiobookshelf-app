import {
  chmodSync,
  closeSync,
  constants,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import { backup, DatabaseSync } from "node:sqlite";
import { createSnapshot, maximumSchemaVersion, readBackup } from "./backup-format.mjs";
import { readiness } from "./diagnostics.mjs";

const [command, ...args] = process.argv.slice(2);
const options = new Map();
for (let n = 0; n < args.length; n += 2) {
  if (!["--backup-dir", "--id", "--destination"].includes(args[n]) || !args[n + 1] || options.has(args[n]))
    throw Error("Use backup or restore --backup-dir PATH --id UUID [--destination PATH]");
  options.set(args[n], args[n + 1]);
}
const directory = resolve(options.get("--destination") || process.env.LEAFWAKE_DATA_DIR || ".data");
try {
  if (command === "diagnose") {
    const result = await readiness(directory);
    let integrity = "unavailable",
      schemaVersion = null;
    try {
      const db = new DatabaseSync(resolve(directory, "leafwake.sqlite"), { readOnly: true });
      try {
        const checked = db.prepare("PRAGMA quick_check(1)").get();
        integrity = Object.values(checked ?? {})[0] === "ok" ? "ok" : "failed";
        schemaVersion = Number(
          db.prepare("SELECT MAX(version) AS version FROM schema_version").get()?.version,
        );
      } finally {
        db.close();
      }
    } catch {}
    if (schemaVersion > maximumSchemaVersion) {
      result.ready = false;
      result.issues.push(
        "This database needs a newer Leafwake image. Preserve the volume and use a compatible image.",
      );
    }
    console.log(JSON.stringify({ ...result, database: { integrity, schemaVersion } }));
    if (!result.ready || integrity !== "ok") process.exitCode = 1;
  } else if (command === "backup") {
    if (!existsSync(resolve(directory, "leafwake.sqlite")))
      throw Error("No installation database exists at the selected data directory");
    const db = new DatabaseSync(resolve(directory, "leafwake.sqlite"), { readOnly: true });
    try {
      console.log(JSON.stringify(await createSnapshot(db, directory)));
    } finally {
      db.close();
    }
  } else if (command === "restore") {
    if (!options.get("--backup-dir") || !options.get("--id"))
      throw Error("Restore requires --backup-dir and --id");
    const copy = readBackup(resolve(options.get("--backup-dir")), options.get("--id"));
    try {
      mkdirSync(directory, { recursive: true, mode: 0o700 });
      if (readdirSync(directory).length)
        throw Error(
          "Destination is populated. Restore into a new empty volume; the current installation was not changed",
        );
      chmodSync(directory, 0o700);
      const marker = resolve(directory, ".restore-in-progress"),
        databaseFile = resolve(directory, "leafwake.sqlite"),
        keyFile = resolve(directory, "token-signing-key"),
        temporary = `${databaseFile}.partial`;
      writeFileSync(
        marker,
        "Restore is incomplete. Keep the original volume and retry into a new empty volume.",
        { flag: "wx", mode: 0o600 },
      );
      for (const path of [marker, directory]) {
        const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
        try {
          fsyncSync(fd);
        } finally {
          closeSync(fd);
        }
      }
      const created = [temporary, keyFile, databaseFile];
      try {
        const deadline = Date.now() + 60_000;
        await backup(copy.db, temporary, {
          progress() {
            if (Date.now() > deadline) throw Error("Restore exceeded its time limit");
          },
        });
        chmodSync(temporary, 0o600);
        writeFileSync(keyFile, copy.key, { flag: "wx", mode: 0o600 });
        for (const path of [temporary, keyFile]) {
          const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
          try {
            fsyncSync(fd);
          } finally {
            closeSync(fd);
          }
        }
        renameSync(temporary, databaseFile);
        const fd = openSync(directory, constants.O_RDONLY);
        try {
          fsyncSync(fd);
        } finally {
          closeSync(fd);
        }
        rmSync(marker);
        const committed = openSync(directory, constants.O_RDONLY);
        try {
          fsyncSync(committed);
        } finally {
          closeSync(committed);
        }
        console.log(
          JSON.stringify({
            restored: true,
            id: copy.manifest.id,
            mediaIncluded: false,
            requiredMounts: copy.manifest.media.requiredMounts,
            managedDirectory: copy.manifest.media.managedDirectory,
            nextStep:
              "Preserve the managed media directory and listed mounts separately, then start this image. Authentication sessions and durable job receipts are retained.",
          }),
        );
      } catch (error) {
        for (const path of created) rmSync(path, { force: true });
        rmSync(marker, { force: true });
        throw error;
      }
    } finally {
      copy.close();
    }
  } else
    throw Error(
      "Use node maintenance.mjs backup, or restore --backup-dir PATH --id UUID into an empty volume",
    );
} catch (error) {
  console.error(
    error instanceof Error && !("code" in error)
      ? error.message
      : "Maintenance failed. Check backup integrity, storage permissions and free space; keep the original volume unchanged.",
  );
  process.exitCode = 1;
}
