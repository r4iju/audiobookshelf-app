import { createServer } from 'node:http'
import { once } from 'node:events'
import { Server } from 'socket.io'

export async function startFixture({ scenario = 'baseline' } = {}) {
  const http = createServer()
  const io = new Server(http, { path: '/abs/socket.io', transports: ['websocket'] })
  const authentications = []
  io.on('connection', socket => {
    socket.on('auth', token => {
      if (token !== 'fresh') return socket.emit('auth_failed', { message: 'Synthetic credentials rejected' })
      authentications.push(token)
      socket.join('qa')
      socket.emit('init', { user: { id: 'qa' }, serverSettings: { version: '2.30.0-fixture' } })
    })
  })
  http.listen(0, '127.0.0.1')
  await once(http, 'listening')
  return {
    address: `http://127.0.0.1:${http.address().port}/abs`,
    authentications,
    progress(data) {
      io.to('qa').emit(scenario === 'progress-event-change' ? 'renamed_progress' : 'user_item_progress_updated', { id: data.libraryItemId, data })
    },
    interrupt() {
      // A transport interruption permits the production client's automatic reconnect policy.
      for (const socket of io.sockets.sockets.values()) socket.conn.close()
    },
    close: () => new Promise(resolve => io.close(resolve))
  }
}
