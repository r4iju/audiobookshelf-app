# Production image of the browser client: a standalone Next.js server, no secrets and no server credentials inside.
# The base path is fixed at build time (Next.js has no runtime base path):
#   docker build --build-arg ABS_WEB_BASE_PATH=/web -t audiobookshelf-web .
ARG NODE_IMAGE=node:22-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c

FROM ${NODE_IMAGE} AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
ARG ABS_WEB_BASE_PATH=""
ENV ABS_WEB_BASE_PATH=${ABS_WEB_BASE_PATH}
RUN npm run build

FROM ${NODE_IMAGE}
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 HOSTNAME=0.0.0.0 PORT=3000
COPY --from=build --chown=node:node /app/.next/standalone ./
COPY --from=build --chown=node:node /app/.next/static ./.next/static
COPY --from=build --chown=node:node /app/public ./public
ARG ABS_WEB_BASE_PATH=""
ENV ABS_WEB_BASE_PATH=${ABS_WEB_BASE_PATH}
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD ["node", "-e", "fetch(`http://127.0.0.1:${process.env.PORT}${process.env.ABS_WEB_BASE_PATH}/connect`).then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
CMD ["node", "server.js"]
