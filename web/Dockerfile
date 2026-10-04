# One product: new Next.js UI, API, persistent accounts and the product-owned HTTP entry.
ARG NODE_IMAGE=node:24-bookworm-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6
FROM ${NODE_IMAGE} AS build
WORKDIR /app
ARG ABS_WEB_BASE_PATH=""
ENV NEXT_TELEMETRY_DISABLED=1 ABS_WEB_BASE_PATH=${ABS_WEB_BASE_PATH}
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build && \
    node --input-type=module -e 'import fs from "node:fs"; const {default:config}=await import("./next.config.ts"); fs.writeFileSync("next.config.mjs",`export default ${JSON.stringify(config)};\n`)' && \
    npm prune --omit=dev --no-audit --no-fund

FROM ${NODE_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ARG ABS_WEB_BASE_PATH=""
ENV ABS_WEB_BASE_PATH=${ABS_WEB_BASE_PATH}
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 HOSTNAME=0.0.0.0 PORT=3000 LEAFWAKE_DATA_DIR=/data LEAFWAKE_MEDIA_ROOTS=/media ABS_WEB_SERVER=${ABS_WEB_BASE_PATH}/
COPY --from=build --chown=node:node /app/package.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/.next ./.next
COPY --from=build --chown=node:node /app/public ./public
COPY --from=build --chown=node:node /app/server.mjs /app/next.config.mjs ./
COPY --from=build --chown=node:node /app/realtime.mjs ./
COPY --from=build --chown=node:node /app/maintenance.mjs /app/backup-format.mjs /app/diagnostics.mjs ./
RUN dpkg-query -W -f='${binary:Package}\t${source:Package}\t${source:Version}\n' > /app/public/ffmpeg-packages.tsv && \
    cp /usr/share/doc/ffmpeg/copyright /app/public/ffmpeg-copyright.txt && \
    mkdir -p /data /media && chown node:node /data /media
USER node
VOLUME ["/data"]
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD ["node", "-e", "fetch(`http://127.0.0.1:${process.env.PORT}${process.env.ABS_WEB_BASE_PATH}/healthz`).then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"]
CMD ["node", "server.mjs"]
