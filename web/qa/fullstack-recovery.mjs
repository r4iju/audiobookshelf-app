import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import test from "node:test";

const base = process.env.LEAFWAKE_RECOVERY_TEST_URL || "http://127.0.0.1:19902";
const image = process.env.LEAFWAKE_RECOVERY_TEST_IMAGE || "leafwake:recovery-170";
const dockerEnv = { ...process.env, DOCKER_HOST: "unix:///Users/emanuel/.colima/default/docker.sock" };
const docker = (args) => execFileSync("docker", args, { env: dockerEnv, encoding: "utf8" });
async function call(path, token, body, origin = base) {
  return fetch(origin + path, {
    method: body === undefined ? "GET" : "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
async function json(path, token, body, origin) {
  const r = await call(path, token, body, origin);
  assert.ok(r.ok, `${path}: ${r.status} ${await r.clone().text()}`);
  return r.json();
}
test("owner backup restores encrypted configuration, policy, sessions and migration receipts in a fresh image with bounded diagnostics", async () => {
  const { user: owner } = await json("/login", "", {
    username: "import-owner",
    password: "synthetic-password-2026",
  });
  const token = owner.accessToken;
  const diagnostics = await json("/api/admin/diagnostics", token);
  assert.equal(diagnostics.database.integrity, "ok");
  assert.equal(diagnostics.tools.ffmpeg.available, true);
  assert.equal(diagnostics.storage.writable, true);
  assert.equal(diagnostics.secrets, undefined);
  const { user: reader } = await json("/login", "", {
    username: "import-user",
    password: "synthetic-password-2026",
  });
  assert.equal((await call("/api/admin/diagnostics", reader.accessToken)).status, 403);
  const before = await json("/api/admin/migrations", token);
  const smtp = await json("/api/emails/settings", token);
  const backup = await json("/api/admin/backups", token, {});
  assert.equal(backup.formatVersion, 2);
  assert.equal(backup.keyIncluded, true);
  assert.equal(backup.media.included, false);
  assert.ok(backup.media.requiredMounts.length > 0);
  const volume = `leafwake-recovery-170-${randomUUID()}`;
  const container = `leafwake-recovery-170-${randomUUID()}`;
  const sourceVolume = process.env.LEAFWAKE_RECOVERY_SOURCE_VOLUME || "leafwake-media-import-158-data-7";
  docker(["volume", "create", volume]);
  try {
    docker([
      "run",
      "--rm",
      "--network",
      "none",
      "-v",
      `${sourceVolume}:/restore:ro`,
      "-v",
      `${volume}:/data`,
      image,
      "node",
      "maintenance.mjs",
      "restore",
      "--backup-dir",
      "/restore/backups",
      "--id",
      backup.id,
    ]);
    const rejected = (() => {
      try {
        docker([
          "run",
          "--rm",
          "--network",
          "none",
          "-v",
          `${sourceVolume}:/restore:ro`,
          "-v",
          `${volume}:/data`,
          image,
          "node",
          "maintenance.mjs",
          "restore",
          "--backup-dir",
          "/restore/backups",
          "--id",
          backup.id,
        ]);
        return false;
      } catch {
        return true;
      }
    })();
    assert.equal(rejected, true, "restore never overwrites a populated destination");
    docker([
      "run",
      "-d",
      "--name",
      container,
      "-p",
      "19912:3000",
      "-v",
      `${volume}:/data`,
      "-v",
      "/Users/emanuel/.cache/leafwake/fullstack-media-154:/Users/emanuel/.cache/leafwake/fullstack-media-154:ro",
      "-e",
      "LEAFWAKE_MEDIA_ROOTS=/Users/emanuel/.cache/leafwake/fullstack-media-154",
      image,
    ]);
    const restored = "http://127.0.0.1:19912";
    for (let n = 0; n < 100; n++) {
      try {
        if ((await fetch(restored + "/healthz")).ok) break;
      } catch {}
      await new Promise((r) => setTimeout(r, 100));
    }
    const after = await json("/api/admin/migrations", token, undefined, restored);
    assert.deepEqual(after, before);
    const restoredSmtp = await json("/api/emails/settings", token, undefined, restored);
    assert.equal(restoredSmtp.hasPassword, smtp.hasPassword);
    const stats = await json("/api/me/listening-stats", reader.accessToken, undefined, restored);
    assert.equal(stats.totalTime, 47);
    assert.equal((await call("/api/users", reader.accessToken, undefined, restored)).status, 403);
    console.log(
      JSON.stringify({
        backupId: backup.id,
        encryptedConfiguration: smtp.hasPassword,
        restoredSeconds: stats.totalTime,
        migrationReceipts: after.migrations.length,
        mediaExcluded: true,
      }),
    );
  } finally {
    try {
      docker(["rm", "-f", container]);
    } catch {}
    docker(["volume", "rm", volume]);
  }
});
