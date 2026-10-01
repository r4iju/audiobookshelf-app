import assert from 'node:assert/strict'
import { once } from 'node:events'
import test from 'node:test'
import socketPlugin from '../../plugins/server.js'
import { startFixture } from './fixture.mjs'

function nextEvent(emitter, name) {
  return once(emitter, name, { signal: AbortSignal.timeout(5000) })
}

test('legacy production socket authenticates under a subpath, applies progress and re-authenticates after reconnect', async () => {
  const fixture = await startFixture()
  const changes = []
  const store = {
    getters: { 'user/getToken': 'fresh' },
    state: { libraries: { numUserPlaylists: 0 } },
    commit: (name, data) => changes.push({ name, data })
  }
  let socket
  socketPlugin({ store }, (_, value) => { socket = value })
  try {
    const initialized = nextEvent(socket, 'initialized')
    socket.connect(fixture.address, 'fresh')
    await initialized
    assert.equal(socket.isAuthenticated, true)
    const progress = nextEvent(socket, 'user_media_progress_updated')
    fixture.progress({ libraryItemId: 'book-0', currentTime: 9, duration: 20, progress: 0.45 })
    assert.equal((await progress)[0].data.currentTime, 9)
    assert.equal(changes.find(value => value.name === 'user/updateUserMediaProgress').data.currentTime, 9)
    const reinitialized = nextEvent(socket, 'initialized')
    fixture.interrupt()
    await reinitialized
    assert.equal(fixture.authentications.length, 2)
    assert.ok(fixture.authentications.every(value => value === 'fresh'))
    assert.ok(changes.some(value => value.name === 'setSocketConnected' && value.data === false))
  } finally {
    socket.logout()
    await fixture.close()
  }
})
