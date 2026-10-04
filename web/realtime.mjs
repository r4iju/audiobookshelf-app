import { Server } from "socket.io";

export function attachRealtime(server, isReady, path = "/socket.io") {
  const io = new Server(server, {
    path,
    serveClient: false,
    maxHttpBufferSize: 16_384,
    connectTimeout: 10_000,
    allowRequest(request, done) {
      const origin = request.headers.origin;
      let allowed = isReady() && io.engine.clientsCount < 256;
      if (origin) {
        try {
          const url = new URL(origin);
          allowed &&=
            ["http:", "https:"].includes(url.protocol) &&
            url.origin === origin &&
            url.host === request.headers.host;
        } catch {
          allowed = false;
        }
      }
      done(null, allowed);
    },
  });
  const clients = new Map();
  let queued = false;
  let catalogDirty = false;
  const usersDirty = new Set();
  const itemsDirty = new Map();
  const denied = (socket, state) => {
    if (state.token) state.deadline = Date.now() + 10_000;
    state.token = null;
    state.snapshot = null;
    socket.emit("auth_failed", { reason: "Sign-in required" });
  };
  const snapshot = (token) => {
    if (!globalThis.leafwakeRealtimeSnapshot) throw new Error("Domain not ready");
    return globalThis.leafwakeRealtimeSnapshot(token);
  };
  function deliver(socket, state) {
    if (!state.token) return;
    try {
      // Synchronous authority and policy reads leave no await gap before publishing.
      const next = snapshot(state.token);
      const before = state.snapshot;
      if (!before || before.user.id !== next.user.id) {
        denied(socket, state);
        return;
      }
      const priorProgress = new Map(before.user.mediaProgress.map((p) => [p.id, JSON.stringify(p)]));
      for (const progress of next.user.mediaProgress)
        if (priorProgress.get(progress.id) !== JSON.stringify(progress))
          socket.emit("user_item_progress_updated", { id: next.user.id, data: progress });
      if (JSON.stringify(before.user) !== JSON.stringify(next.user)) socket.emit("user_updated", next.user);
      if (before.items !== next.items) {
        const previous = new Map(before.items.map((item) => [item.id, JSON.stringify(item)]));
        const current = new Set(next.items.map((item) => item.id));
        const added = [],
          updated = [];
        for (const item of next.items) {
          if (!previous.has(item.id)) added.push(item);
          else if (previous.get(item.id) !== JSON.stringify(item)) updated.push(item);
        }
        for (const id of previous.keys()) if (!current.has(id)) socket.emit("item_removed", { id });
        if (added.length) socket.emit("items_added", added);
        if (updated.length) socket.emit("items_updated", updated);
      }
      state.snapshot = next;
    } catch {
      denied(socket, state);
    }
  }
  globalThis.leafwakeRealtimeChanged = (change) => {
    if (change?.catalog) catalogDirty = true;
    if (change?.userId) usersDirty.add(change.userId);
    if (change?.userId && change?.itemId) {
      const items = itemsDirty.get(change.userId) ?? new Set();
      items.add(change.itemId);
      itemsDirty.set(change.userId, items);
    }
    if (queued) return;
    queued = true;
    queueMicrotask(() => {
      queued = false;
      for (const [socket, state] of clients) {
        if (!state.token) continue;
        try {
          globalThis.leafwakeRealtimeCheck(state.token);
        } catch {
          denied(socket, state);
          continue;
        }
        if (catalogDirty || usersDirty.has(state.snapshot?.user.id)) deliver(socket, state);
        if (state.token)
          for (const id of itemsDirty.get(state.snapshot?.user.id) ?? []) {
            try {
              const item = globalThis.leafwakeRealtimeItem(state.token, id);
              socket.emit("items_updated", [item]);
            } catch {
              /* A now-inaccessible item carries no metadata. */
            }
          }
      }
      catalogDirty = false;
      usersDirty.clear();
      itemsDirty.clear();
    });
  };
  io.on("connection", (socket) => {
    const state = {
      token: null,
      snapshot: null,
      attempts: 0,
      window: Date.now(),
      deadline: Date.now() + 10_000,
    };
    clients.set(socket, state);
    socket.on("auth", (token) => {
      if (Date.now() - state.window > 60_000) {
        state.window = Date.now();
        state.attempts = 0;
      }
      if (++state.attempts > 30) {
        socket.disconnect(true);
        return;
      }
      if (typeof token !== "string" || token.length > 1024) {
        denied(socket, state);
        return;
      }
      try {
        const current = snapshot(token);
        state.token = token;
        state.snapshot = current;
        socket.emit("init", {
          userId: current.user.id,
          user: current.user,
          serverSettings: { version: "1.0.0-dev" },
        });
      } catch {
        denied(socket, state);
      }
    });
    socket.on("disconnect", () => clients.delete(socket));
  });
  const expiry = setInterval(() => {
    for (const [socket, state] of clients) {
      if (!state.token) {
        if (Date.now() >= state.deadline) socket.disconnect(true);
        continue;
      }
      try {
        if (!globalThis.leafwakeRealtimeCheck) throw new Error("Domain not ready");
        globalThis.leafwakeRealtimeCheck(state.token);
      } catch {
        denied(socket, state);
      }
    }
  }, 1000);
  expiry.unref();
  return () => {
    clearInterval(expiry);
    globalThis.leafwakeRealtimeChanged = undefined;
    io.disconnectSockets(true);
    io.close();
  };
}
