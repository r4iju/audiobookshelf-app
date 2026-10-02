// A streamed playback session's progress follows the server's finished rule whether or not progress exists yet:
// its sync carries no finished flag, so a first sync within 10 s of the end is finished, and a sync part way is not.
// Pinned 2.30.0 fails the first case (its create branch skips the rule). Run against a freshly seeded synthetic server
// (web/qa/server.mjs up --fresh) as its `qa-other` account:
//   node streamed-first-progress-check.mjs http://127.0.0.1:19890
// Exits 1 when any case fails. It writes progress and sessions for the qa-other account only.
const base = process.argv[2] ?? "http://127.0.0.1:19890";
const login = await (
  await fetch(`${base}/login`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-return-tokens": "true" },
    body: JSON.stringify({ username: "qa-other", password: "qa-other-pass" }),
  })
).json();
const headers = { authorization: `Bearer ${login.user.accessToken}`, "content-type": "application/json" };
const call = async (path, method = "GET", body) => {
  const response = await fetch(base + path, { method, headers, body: body && JSON.stringify(body) });
  const text = await response.text();
  return { status: response.status, body: text.startsWith("{") ? JSON.parse(text) : text };
};
const { libraries } = (await call("/api/libraries")).body;
const books = (await call(`/api/libraries/${libraries.find((l) => l.mediaType === "book").id}/items?limit=200`)).body
  .results;
const book = (title) => books.find((item) => item.media.metadata.title === title);

const results = [];
const check = (name, actual, expected) => {
  const pass = Object.entries(expected).every(([key, value]) => actual?.[key] === value);
  results.push({ name, pass, expected, actual });
};
const read = async (item) => {
  const { status, body } = await call(`/api/me/progress/${item.id}`);
  if (status !== 200) return { status };
  return { status, currentTime: body.currentTime, isFinished: body.isFinished };
};
const clear = async (item) => {
  const { body } = await call(`/api/me/progress/${item.id}`);
  if (body?.id) await call(`/api/me/progress/${body.id}`, "DELETE");
  return (await call(`/api/me/progress/${item.id}`)).status;
};
const play = async (item) =>
  (
    await call(`/api/items/${item.id}/play`, "POST", {
      deviceInfo: { deviceId: "streamed-first-progress-check", clientName: "streamed-first-progress-check" },
      mediaPlayer: "html5",
      forceDirectPlay: true,
      supportedMimeTypes: ["audio/mpeg"],
    })
  ).body;
const sync = async (session, currentTime) =>
  (await call(`/api/session/${session.id}/sync`, "POST", { currentTime, timeListened: 5, duration: session.duration }))
    .status;
const closeSession = (session) => call(`/api/session/${session.id}/close`, "POST", {});

// First progress from a streamed sync 5 s before the end.
const ended = book("Salt and Signal");
check("no progress before the first streamed sync", { status: await clear(ended) }, { status: 404 });
let session = await play(ended);
const nearEnd = session.duration - 5;
check("first streamed sync is answered 200", { status: await sync(session, nearEnd) }, { status: 200 });
check("a first streamed sync 5 s before the end is finished", await read(ended), {
  currentTime: nearEnd,
  isFinished: true,
});
await closeSession(session);

// First progress from a streamed sync part way.
const partial = book("The Long Tide");
await clear(partial);
session = await play(partial);
await sync(session, 20);
check("a first streamed sync part way is not finished", await read(partial), { currentTime: 20, isFinished: false });
// A later sync near the end updates the existing progress to finished, as on every server.
await sync(session, session.duration - 5);
check("a later streamed sync 5 s before the end finishes existing progress", await read(partial), {
  isFinished: true,
});
await closeSession(session);
await clear(ended);
await clear(partial);

for (const r of results)
  console.log(
    `${r.pass ? "PASS" : "FAIL"} ${r.name}${r.pass ? "" : `\n  expected ${JSON.stringify(r.expected)}\n  actual   ${JSON.stringify(r.actual)}`}`,
  );
process.exit(results.every((r) => r.pass) ? 0 : 1);
