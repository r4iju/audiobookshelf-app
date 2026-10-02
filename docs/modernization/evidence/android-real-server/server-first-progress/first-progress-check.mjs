// Progress created by a title's first local session must follow the same rules as progress that already exists:
// finished at its end, stamped with the session's own updatedAt, and never newer than a later write from another
// device. Run against a freshly seeded synthetic server (web/qa/server.mjs up --fresh) as its `qa` account:
//   node first-progress-check.mjs http://127.0.0.1:28870
// Exits 1 when any case fails. It writes progress for the qa account only.
const base = process.argv[2] ?? 'http://127.0.0.1:28870'
const login = await (await fetch(`${base}/login`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-return-tokens': 'true' }, body: JSON.stringify({ username: 'qa', password: 'qa-pass' }) })).json()
const headers = { authorization: `Bearer ${login.user.accessToken}`, 'content-type': 'application/json' }
const call = async (path, method = 'GET', body) => {
  const response = await fetch(base + path, { method, headers, body: body && JSON.stringify(body) })
  const text = await response.text()
  return { status: response.status, body: text.startsWith('{') ? JSON.parse(text) : text }
}
const { libraries } = (await call('/api/libraries')).body
const library = async (type) => (await call(`/api/libraries/${libraries.find((l) => l.mediaType === type).id}/items?limit=200`)).body.results
const books = await library('book')
const book = (title) => books.find((item) => item.media.metadata.title === title)
const podcast = (await call(`/api/items/${(await library('podcast'))[0].id}?expanded=1`)).body
const episode = podcast.media.episodes.find((e) => e.title.startsWith('Episode 1'))

const session = (item, { currentTime, updatedAt, episodeId = null, duration = item.media.duration }) => ({
  id: crypto.randomUUID(), libraryItemId: item.id, episodeId, mediaType: episodeId ? 'podcast' : 'book',
  mediaMetadata: {}, displayTitle: item.media.metadata.title, displayAuthor: '', duration, playMethod: 3,
  mediaPlayer: 'exo-player', startTime: 0, currentTime, timeListening: currentTime, startedAt: updatedAt - currentTime * 1000, updatedAt
})
const sync = (sessions, deviceId = 'first-progress-check') => call('/api/session/local-all', 'POST', { sessions, deviceInfo: { deviceId, clientName: 'first-progress-check' } })
const progress = async (item, episodeId) => {
  const { body } = await call(`/api/me/progress/${item.id}${episodeId ? `/${episodeId}` : ''}`)
  return typeof body === 'string' ? body : { currentTime: body.currentTime, isFinished: body.isFinished, lastUpdate: body.lastUpdate }
}

const results = []
const check = (name, actual, expected) => {
  const pass = Object.entries(expected).every(([key, value]) => actual?.[key] === value)
  results.push({ name, pass, expected, actual })
}
const now = Date.now()

// A title's first progress comes from a session that played to the end offline.
const ended = book('A Very Long Story Title')
const endedSession = session(ended, { currentTime: ended.media.duration, updatedAt: now - 60_000 })
await sync([endedSession])
check('first session at its end is finished and keeps its own time', await progress(ended), { currentTime: ended.media.duration, isFinished: true, lastUpdate: endedSession.updatedAt })
await sync([endedSession])
check('the same session sent again changes nothing', await progress(ended), { isFinished: true, lastUpdate: endedSession.updatedAt })

// A first session stopped part way is not finished, and keeps its own time.
const partial = book('Salt and Signal')
const partialSession = session(partial, { currentTime: 5, updatedAt: now - 50_000 })
await sync([partialSession])
check('first session part way is not finished and keeps its own time', await progress(partial), { currentTime: 5, isFinished: false, lastUpdate: partialSession.updatedAt })

// Another device listened later than an offline session that only now reaches the server.
const shared = book('The Long Tide')
const other = session(shared, { currentTime: 40, updatedAt: now - 40_000 })
await sync([other], 'other-device')
check('first session from another device keeps its own time', await progress(shared), { currentTime: 40, isFinished: false, lastUpdate: other.updatedAt })
await sync([session(shared, { currentTime: shared.media.duration, updatedAt: now - 45_000 })])
check('an older offline session does not replace newer listening from another device', await progress(shared), { currentTime: 40, isFinished: false, lastUpdate: other.updatedAt })
const later = session(shared, { currentTime: shared.media.duration, updatedAt: now - 30_000 })
await sync([later])
check('a newer offline session that reached the end finishes it', await progress(shared), { isFinished: true, lastUpdate: later.updatedAt })

// A podcast episode's first progress, finished offline, with the episode's own duration.
const episodeSession = session(podcast, { currentTime: episode.audioFile.duration, updatedAt: now - 20_000, episodeId: episode.id, duration: episode.audioFile.duration })
await sync([episodeSession])
check('first episode session at its end is finished and keeps its own time', await progress(podcast, episode.id), { isFinished: true, lastUpdate: episodeSession.updatedAt })

// A reading position creates progress through PATCH; it has no audio and is not finished.
const pdf = book('Field Guide to Quiet')
await call(`/api/me/progress/${pdf.id}`, 'PATCH', { ebookLocation: '3', ebookProgress: 0.025 })
check('first reading position through PATCH is not finished', await progress(pdf), { isFinished: false })

for (const r of results) console.log(`${r.pass ? 'PASS' : 'FAIL'} ${r.name}${r.pass ? '' : `\n  expected ${JSON.stringify(r.expected)}\n  actual   ${JSON.stringify(r.actual)}`}`)
process.exit(results.every((r) => r.pass) ? 0 : 1)
