// Progress a client creates through PATCH /api/me/progress must keep what the client sent, as pinned 2.30.0 does:
// a first position part way is not finished, whatever the time left. Only an update to existing progress applies the
// server's finished rule (less than 10 s left), and that must stay as it is. Run against a freshly seeded synthetic
// server (web/qa/server.mjs up --fresh) as its `qa-other` account:
//   node patch-first-progress-check.mjs http://127.0.0.1:19890
// Exits 1 when any case fails. It writes progress for the qa-other account only.
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
const library = async (type) =>
  (await call(`/api/libraries/${libraries.find((l) => l.mediaType === type).id}/items?limit=200`)).body.results;
const book = (await library("book")).find((item) => item.media.metadata.title === "The Long Tide");
const podcast = (await call(`/api/items/${(await library("podcast"))[0].id}?expanded=1`)).body;
const episode = podcast.media.episodes.find((e) => e.title.startsWith("Episode 3"));
const targets = {
  book: { path: book.id, duration: book.media.duration },
  episode: { path: `${podcast.id}/${episode.id}`, duration: episode.audioFile.duration },
};

const results = [];
const check = (name, actual, expected) => {
  const pass = Object.entries(expected).every(([key, value]) => actual?.[key] === value);
  results.push({ name, pass, expected, actual });
};
const read = async (path) => {
  const { status, body } = await call(`/api/me/progress/${path}`);
  if (status !== 200) return { status };
  const { currentTime, duration, progress, isFinished } = body;
  return { status, currentTime, duration, progress, isFinished };
};
const clear = async (path) => {
  const { body } = await call(`/api/me/progress/${path}`);
  if (body?.id) await call(`/api/me/progress/${body.id}`, "DELETE");
  return (await call(`/api/me/progress/${path}`)).status;
};
const patch = async (path, body) => (await call(`/api/me/progress/${path}`, "PATCH", body)).status;

for (const [kind, { path, duration }] of Object.entries(targets)) {
  // 9 s before the end: inside the 10 s finished threshold of an update.
  const nearEnd = duration - 9;
  const progress = Math.round((nearEnd / duration) * 100) / 100;

  check(`${kind}: no progress before the first PATCH`, { status: await clear(path) }, { status: 404 });
  const sent = { currentTime: nearEnd, duration, progress };
  check(`${kind}: first PATCH is answered 200`, { status: await patch(path, sent) }, { status: 200 });
  check(`${kind}: a first position 9 s before the end keeps the sent progress, not finished`, await read(path), {
    currentTime: nearEnd,
    progress,
    isFinished: false,
  });
  await patch(path, sent);
  check(`${kind}: the same PATCH on existing progress is finished by the update rule`, await read(path), {
    currentTime: nearEnd,
    progress: 1,
    isFinished: true,
  });

  await clear(path);
  await patch(path, { currentTime: nearEnd, duration });
  check(`${kind}: a first position without progress is not finished`, await read(path), {
    currentTime: nearEnd,
    progress: 0,
    isFinished: false,
  });

  // Control: far from the end, no server finishes a first position.
  await clear(path);
  await patch(path, { currentTime: 1, duration, progress: 0.01 });
  check(`${kind}: a first position 1 s into it, far from the end, is not finished`, await read(path), {
    currentTime: 1,
    progress: 0.01,
    isFinished: false,
  });

  await clear(path);
  await patch(path, { currentTime: 3, duration, progress: 0.01, isFinished: true });
  check(`${kind}: a first PATCH sending isFinished is finished`, await read(path), { progress: 1, isFinished: true });

  // The batch form creates and updates through the same function.
  await clear(path);
  const [libraryItemId, episodeId] = path.split("/");
  const batch = async () =>
    (await call("/api/me/progress/batch/update", "PATCH", [{ libraryItemId, episodeId, ...sent }])).status;
  check(`${kind}: batch PATCH is answered 200`, { status: await batch() }, { status: 200 });
  check(`${kind}: a first batch position 9 s before the end keeps the sent progress, not finished`, await read(path), {
    currentTime: nearEnd,
    progress,
    isFinished: false,
  });
  await batch();
  check(`${kind}: the same batch PATCH on existing progress is finished by the update rule`, await read(path), {
    progress: 1,
    isFinished: true,
  });
  await clear(path);
}

for (const r of results)
  console.log(
    `${r.pass ? "PASS" : "FAIL"} ${r.name}${r.pass ? "" : `\n  expected ${JSON.stringify(r.expected)}\n  actual   ${JSON.stringify(r.actual)}`}`,
  );
process.exit(results.every((r) => r.pass) ? 0 : 1);
