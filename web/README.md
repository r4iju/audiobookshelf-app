# Audiobook Loft full stack

Next.js browser UI and a new TypeScript backend, packaged together with Socket.IO and bounded media jobs on one Node listener. SQLite accounts, sessions, catalog and progress persist in `/data`. Original media mounts are read-only. No original Audiobookshelf process is required.

- [Deployment](docs/DEPLOYMENT.md)
- [Compatibility contract](docs/SERVER-CONTRACT.md)
- [Migration and rollback](../docs/fullstack/MIGRATION.md)
- [Rewrite scope and evidence](../docs/fullstack/STATE.md)

Use Node 24 and npm. Run `npm ci` in this directory. `npm run dev` starts the custom product entry. `npm run build` compiles Next.js; `npm start` runs the custom entry with that build. Do not launch the generated standalone entry, which does not include the custom listener or workers.

Checks: `npm run typecheck`, `npm run lint`, `npm run i18n:validate`, `npm test`. `npm run e2e` starts a private synthetic product installation and runs the existing browser journeys. `LEAFWAKE_QA_IMAGE=<built-tag>` selects an exact image. QA never uses owner data. `node qa/server.mjs down` removes only its named synthetic containers and volume.

Default loopback QA ports: product 19880; subpath deployment 19882; OpenID 19884; feed 19885; SMTP sink 19886. The fixture helpers use the same image and share the product network namespace. They are excluded from the production image. Subpath QA replaces the root QA container sequentially on its private volume, never running two SQLite writers. Native QA uses separate ports and volumes.
