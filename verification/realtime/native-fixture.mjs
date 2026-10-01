import { createServer, request } from 'node:http'
import { Server } from 'socket.io'

const port = Number(process.argv[2] ?? 19765)
const backend = Number(process.argv[3] ?? 19769)
const http = createServer((incoming, outgoing) => {
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
      const response = await fetch(`http://127.0.0.1:${backend}/abs/__fixture__/realtime-auth`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token }) })
      if (!response.ok) return socket.emit('auth_failed', { message: 'Synthetic credentials rejected' })
      const { userId } = await response.json()
      socket.join('authenticated')
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
    if (response.ok) for (const event of await response.json()) io.to('authenticated').emit(event.name, event.data)
  } catch {} finally { polling = false }
}, 250)
http.listen(port, '127.0.0.1')
const stop = () => { clearInterval(interval); io.close(() => process.exit(0)) }
process.on('SIGTERM', stop)
process.on('SIGINT', stop)
