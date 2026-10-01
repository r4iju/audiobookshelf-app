import { once } from 'node:events'
import socketPlugin from '../../plugins/server.js'
import { startFixture } from './fixture.mjs'

const scenario = process.argv[2] || 'baseline'
if (!['baseline', 'progress-event-change'].includes(scenario)) throw new Error('Unknown synthetic scenario')
const fixture = await startFixture({ scenario })
const changes = []
const store = {
  getters: { 'user/getToken': 'fresh' },
  state: { libraries: { numUserPlaylists: 0 } },
  commit: (name, data) => changes.push({ name, data })
}
let socket
socketPlugin({ store }, (_, value) => { socket = value })
let workflow = 'realtime-authentication'
let report
try {
  const initialized = once(socket, 'initialized', { signal: AbortSignal.timeout(5000) })
  socket.connect(fixture.address, 'fresh')
  await initialized
  workflow = 'realtime-progress'
  const progress = once(socket, 'user_media_progress_updated', { signal: AbortSignal.timeout(3000) })
  fixture.progress({ libraryItemId: 'book-0', currentTime: 9, duration: 20, progress: 0.45 })
  await progress
  if (!changes.some(value => value.name === 'user/updateUserMediaProgress' && value.data.currentTime === 9)) throw new Error('Progress was not applied')
  workflow = 'realtime-reconnection'
  const reinitialized = once(socket, 'initialized', { signal: AbortSignal.timeout(5000) })
  fixture.interrupt()
  await reinitialized
  if (fixture.authentications.length !== 2) throw new Error('Reconnect did not authenticate')
  report = { client: 'legacy-ServerSocket', result: 'passed', workflows: ['realtime-authentication', 'realtime-progress', 'realtime-reconnection'] }
} catch {
  report = { client: 'legacy-ServerSocket', result: 'failed', workflow, reason: 'Candidate no longer satisfies the shipped realtime workflow.' }
  process.exitCode = 1
} finally {
  socket.logout()
  await fixture.close()
}

console.log(JSON.stringify(report))
