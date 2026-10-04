import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { io } from "socket.io-client";

const base = process.env.LEAFWAKE_REALTIME_TEST_URL || "http://127.0.0.1:19893";
async function call(path, token, data, method = data === undefined ? "GET" : "POST") {
  const r = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: "Bearer " + token } : {}),
      ...(data === undefined ? {} : { "content-type": "application/json" }),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  assert.ok(r.ok, `${method} ${path}: ${r.status}`);
  return r.json();
}
async function login(name, password = "synthetic-password-2026") {
  return (await call("/login", null, { username: name, password })).user;
}
function once(socket, event, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off(event, done);
      reject(Error("Missing " + event));
    }, timeout);
    function done(data) {
      clearTimeout(timer);
      resolve(data);
    }
    socket.once(event, done);
  });
}
async function connect(t, transport = "websocket") {
  const socket = io(base, {
    autoConnect: false,
    reconnection: false,
    transports: [transport],
    timeout: 2500,
  });
  t.after(() => socket.disconnect());
  const connected = once(socket, "connect");
  socket.connect();
  await connected;
  return socket;
}
async function auth(socket, token) {
  const init = once(socket, "init");
  socket.emit("auth", token);
  return init;
}
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
test("one-image realtime authenticates current accounts, isolates committed progress and catalog, revokes and reconnects", async (t) => {
  const owner = await login("legacy-owner");
  const suffix = randomUUID();
  const alice = await call("/api/users", owner.accessToken, {
    username: "rt-a-" + suffix,
    password: "synthetic-password-2026",
    type: "user",
  });
  const bob = await call("/api/users", owner.accessToken, {
    username: "rt-b-" + suffix,
    password: "synthetic-password-2026",
    type: "user",
    permissions: { accessAllLibraries: false },
    librariesAccessible: [],
  });
  const a = await login(alice.username),
    b = await login(bob.username);
  const libraries = (await call("/api/libraries", owner.accessToken)).libraries;
  const library = libraries.find((l) => l.name === "Native real journeys");
  assert.ok(library);
  const items = (await call(`/api/libraries/${library.id}/items?limit=100`, owner.accessToken)).results;
  const book = items.find((i) => i.media.metadata.title === "The Long Tide");
  assert.ok(book);
  const sa = await connect(t),
    sb = await connect(t, "polling");
  assert.equal((await auth(sa, a.accessToken)).userId, a.id);
  assert.equal((await auth(sb, b.accessToken)).userId, b.id);
  let bobLeaks = 0;
  for (const e of [
    "user_item_progress_updated",
    "item_updated",
    "item_added",
    "items_updated",
    "items_added",
  ])
    sb.on(e, () => bobLeaks++);
  const resetEvent = once(sa, "items_updated");
  const reset = await call(`/api/me/progress/${book.id}/reset`, a.accessToken, { resetId: randomUUID() });
  assert.ok(
    (await resetEvent).some((i) => i.id === book.id && i.progressGeneration === reset.progressGeneration),
    "empty reset invalidates the other device’s generation",
  );
  const progress = once(sa, "user_item_progress_updated");
  await call(
    `/api/me/progress/${book.id}`,
    a.accessToken,
    { currentTime: 17, isFinished: false, progressGeneration: reset.progressGeneration },
    "PATCH",
  );
  const update = await progress;
  assert.equal(update.data.libraryItemId, book.id);
  assert.equal(update.data.currentTime, 17);
  assert.equal(update.id, a.id);
  assert.equal(
    (await call(`/api/me/progress/${book.id}`, a.accessToken)).currentTime,
    17,
    "event follows committed REST data",
  );
  const user = once(sa, "user_updated");
  await call(
    `/api/me/progress/${book.id}`,
    a.accessToken,
    { isFinished: true, progressGeneration: reset.progressGeneration },
    "PATCH",
  );
  assert.ok((await user).mediaProgress.some((p) => p.libraryItemId === book.id && p.isFinished));
  const changed = once(sa, "items_updated");
  await call(`/api/libraries/${library.id}/scan`, owner.accessToken, {});
  assert.ok((await changed).some((i) => i.id === book.id));
  const fresh = once(sa, "init");
  sa.emit("auth", a.accessToken);
  assert.equal((await fresh).userId, a.id);
  const denied = once(sa, "auth_failed");
  await call(`/api/users/${a.id}/revoke`, owner.accessToken, {});
  await denied;
  const deniedAgain = once(sa, "auth_failed");
  sa.emit("auth", a.accessToken);
  await deniedAgain;
  const renewed = await login(a.username);
  assert.equal((await auth(sa, renewed.accessToken)).userId, a.id);
  sa.disconnect();
  sa.connect();
  await once(sa, "connect");
  assert.equal((await auth(sa, renewed.accessToken)).userId, a.id);
  const rejected = once(sb, "auth_failed");
  sb.emit("auth", "invalid-token");
  await rejected;
  await pause(1100);
  assert.equal(bobLeaks, 0, "another account cannot receive private progress or inaccessible media");
});

test("raw Apple and TV protocol sees an auth_failed event with its required payload", async () => {
  const url = new URL(base);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/socket.io/";
  url.search = "EIO=4&transport=websocket";
  const socket = new WebSocket(url);
  try {
    const packet = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(Error("Native wire did not receive auth rejection")), 5000);
      socket.addEventListener("message", (event) => {
        const text = String(event.data);
        if (text.startsWith("0")) socket.send("40");
        else if (text.startsWith("40")) socket.send("42" + JSON.stringify(["auth", "invalid-token"]));
        else if (text.startsWith("42")) {
          clearTimeout(timeout);
          resolve(JSON.parse(text.slice(2)));
        }
      });
      socket.addEventListener("error", () => {
        clearTimeout(timeout);
        reject(Error("WebSocket failed"));
      });
    });
    assert.equal(packet[0], "auth_failed");
    assert.equal(packet.length, 2, "Apple/TV require name and payload");
  } finally {
    socket.close();
  }
});
