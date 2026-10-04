import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { io } from "socket.io-client";

const base = process.env.LEAFWAKE_LISTS_TEST_URL || "http://127.0.0.1:19902";
async function call(path, token, data, method = data === undefined ? "GET" : "POST") {
  return fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(data === undefined ? {} : { "content-type": "application/json" }),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function json(path, token, data, method) {
  const result = await call(path, token, data, method);
  assert.ok(result.ok, `${path}: ${result.status} ${await result.clone().text()}`);
  return result.json();
}
function event(socket, name) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off(name, done);
      reject(new Error(`No ${name}`));
    }, 3000);
    function done(value) {
      clearTimeout(timer);
      resolve(value);
    }
    socket.once(name, done);
  });
}
test("authorized lists retain order, membership, ownership and scoped realtime", async () => {
  const owner = (
    await json("/login", null, { username: "import-owner", password: "synthetic-password-2026" })
  ).user;
  const libraries = await json("/api/libraries", owner.accessToken);
  const library = libraries.libraries.find((l) => l.name.startsWith("Discovery "));
  assert.ok(library);
  const books = (
    await json(`/api/libraries/${library.id}/items?limit=40&sort=media.metadata.title`, owner.accessToken)
  ).results;
  const token = owner.accessToken;
  const user = await json("/api/users", token, {
    username: `lists-${randomUUID()}`,
    password: "synthetic-list-password",
    librariesAccessible: [library.id],
    itemTagsSelected: ["public"],
    permissions: { accessAllTags: false, accessAllLibraries: false },
  });
  let other = (await json("/login", null, { username: user.username, password: "synthetic-list-password" }))
    .user;
  const socket = io(base, { transports: ["websocket"] });
  try {
    const initialized = event(socket, "init");
    socket.on("connect", () => socket.emit("auth", other.accessToken));
    await initialized;
    const added = event(socket, "collection_added");
    const collection = await json("/api/collections", token, {
      libraryId: library.id,
      name: "Synthetic ordered collection",
      description: "Visible collection",
      books: [books[2].id, books[0].id, books[39].id],
    });
    const notice = await added;
    assert.equal(notice.id, collection.id);
    assert.deepEqual(
      notice.books.map((b) => b.id),
      [books[2].id, books[0].id],
      "realtime filters hidden members",
    );
    assert.deepEqual(
      collection.books.map((b) => b.id),
      [books[2].id, books[0].id, books[39].id],
    );
    assert.equal(
      (await call(`/api/collections/${collection.id}`, other.accessToken, { name: "Denied" }, "PATCH"))
        .status,
      403,
    );
    const edited = await json(
      `/api/collections/${collection.id}`,
      token,
      { name: "Renamed collection", books: [books[0].id, books[2].id] },
      "PATCH",
    );
    assert.deepEqual(
      edited.books.map((b) => b.id),
      [books[0].id, books[2].id],
    );
    await json(`/api/collections/${collection.id}/batch/add`, token, { books: [books[1].id, books[1].id] });
    const compact = await json(`/api/collections/${collection.id}/batch/remove`, token, {
      books: [books[2].id],
    });
    assert.deepEqual(
      compact.books.map((b) => b.id),
      [books[0].id, books[1].id],
    );
    const playlist = await json("/api/playlists", other.accessToken, {
      libraryId: library.id,
      name: "Private playlist",
      items: [{ libraryItemId: books[0].id }, { libraryItemId: books[1].id }],
    });
    assert.equal(
      (await call(`/api/playlists/${playlist.id}`, token)).status,
      404,
      "playlist is account scoped even for owner",
    );
    const changed = await json(
      `/api/playlists/${playlist.id}`,
      other.accessToken,
      { name: "Reordered playlist", items: [{ libraryItemId: books[1].id }, { libraryItemId: books[0].id }] },
      "PATCH",
    );
    assert.deepEqual(
      changed.items.map((i) => i.libraryItemId),
      [books[1].id, books[0].id],
    );
    assert.equal(
      (
        await call(`/api/playlists/${playlist.id}/batch/add`, other.accessToken, {
          items: [{ libraryItemId: books[39].id }],
        })
      ).status,
      404,
    );
    const entry = changed.items[0].libraryItem;
    const session = await json(`/api/items/${entry.id}/play`, other.accessToken, {
      supportedMimeTypes: ["audio/wav"],
    });
    assert.equal(session.libraryItemId, entry.id);
    await json(`/api/session/${session.id}/close`, other.accessToken, {});
    const listed = await json(`/api/libraries/${library.id}/playlists`, other.accessToken);
    assert.ok(listed.results.some((p) => p.id === playlist.id));
    await json(`/api/users/${user.id}`, token, { permissions: { accessAllTags: true } }, "PATCH");
    other = (await json("/login", null, { username: user.username, password: "synthetic-list-password" }))
      .user;
    const retained = await json("/api/playlists", other.accessToken, {
      libraryId: library.id,
      name: "Retained hidden membership",
      items: [{ libraryItemId: books[0].id }, { libraryItemId: books[39].id }],
    });
    await json(`/api/users/${user.id}`, token, { permissions: { accessAllTags: false } }, "PATCH");
    other = (await json("/login", null, { username: user.username, password: "synthetic-list-password" }))
      .user;
    const visible = await json(`/api/playlists/${retained.id}`, other.accessToken);
    assert.equal(visible.items.length, 1);
    await json(
      `/api/playlists/${retained.id}`,
      other.accessToken,
      {
        name: "Native metadata rename",
        items: visible.items.map(({ libraryItemId, episodeId }) => ({ libraryItemId, episodeId })),
      },
      "PATCH",
    );
    await json(`/api/users/${user.id}`, token, { permissions: { accessAllTags: true } }, "PATCH");
    other = (await json("/login", null, { username: user.username, password: "synthetic-list-password" }))
      .user;
    assert.equal(
      (await json(`/api/playlists/${retained.id}`, other.accessToken)).items.length,
      2,
      "visible metadata save must retain hidden members",
    );
    console.log(
      `Lists restart fixture collection ${collection.id} playlist ${playlist.id} user ${user.username}`,
    );
    assert.equal((await call(`/api/collections/${collection.id}`, token, undefined, "DELETE")).status, 200);
    assert.equal((await call(`/api/collections/${collection.id}`, token)).status, 404);
  } finally {
    socket.disconnect();
  }
});
