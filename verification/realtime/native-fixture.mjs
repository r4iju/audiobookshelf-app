import { createServer, request } from 'node:http'
import { Server } from 'socket.io'

const port = Number(process.argv[2] ?? 19765)
const backend = Number(process.argv[3] ?? 19769)
// While held, sockets connect but are not authenticated, the window between an API load and `init`.
let held = null
const http = createServer((incoming, outgoing) => {
  if (incoming.url === '/abs/__fixture__/realtime-hold' && incoming.method === 'POST') {
    let body = ''
    incoming.on('data', chunk => { body += chunk })
    incoming.on('end', () => {
      const hold = JSON.parse(body || '{}').hold === true
      if (hold && !held) { let release; const promise = new Promise(resolve => { release = resolve }); held = { promise, release } }
      if (!hold && held) { held.release(); held = null }
      outgoing.writeHead(200, { 'Content-Type': 'application/json' })
      outgoing.end('{}')
    })
    return
  }
  if (incoming.url === '/abs/__fixture__/realtime-connections') {
    // Authenticated sockets currently open per user, so journeys can observe account isolation.
    const open = {}
    for (const socket of io.sockets.sockets.values()) if (socket.data.userId) open[socket.data.userId] = (open[socket.data.userId] ?? 0) + 1
    outgoing.writeHead(200, { 'Content-Type': 'application/json' })
    return outgoing.end(JSON.stringify(open))
  }
  const upstream = request({ hostname: '127.0.0.1', port: backend, path: incoming.url, method: incoming.method, headers: incoming.headers }, response => {
    outgoing.writeHead(response.statusCode, response.headers)
    response.pipe(outgoing)
  })
  upstream.on('error', () => { if (!outgoing.headersSent) outgoing.writeHead(503); outgoing.end() })
  incoming.pipe(upstream)
})
const io = new Server(http, { path: '/abs/socket.io', transports: ['websocket'] })
io.on('connection', socket => {
  socket.on('auth', async token => {
    try {
      while (held) await held.promise
      if (socket.disconnected) return
      const response = await fetch(`http://127.0.0.1:${backend}/abs/__fixture__/realtime-auth`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token }) })
      if (!response.ok) return socket.emit('auth_failed', { message: 'Synthetic credentials rejected' })
      const { userId } = await response.json()
      socket.data.userId = userId
      socket.join('authenticated')
      socket.join('user:' + userId)
      socket.emit('init', { userId })
    } catch { socket.disconnect(true) }
  })
})
let polling = false
const interval = setInterval(async () => {
  if (polling) return
  polling = true
  try {
    const response = await fetch(`http://127.0.0.1:${backend}/abs/__fixture__/realtime-events`)
    if (response.ok) for (const event of await response.json()) {
      // A transport interruption permits the production client's automatic reconnect policy.
      if (event.name === '__disconnect__') for (const socket of io.sockets.sockets.values()) socket.conn.close()
      else io.to(event.userId ? 'user:' + event.userId : 'authenticated').emit(event.name, event.data)
    }
  } catch {} finally { polling = false }
}, 250)
http.listen(port, '127.0.0.1')
const stop = () => { clearInterval(interval); io.close(() => process.exit(0)) }
process.on('SIGTERM', stop)
process.on('SIGINT', stop)
