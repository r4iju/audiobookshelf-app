# Audiobook Loft

Audiobook Loft is an independent self-hosted audiobook and ebook library with native Android, Apple and TV clients. One product image serves the Next.js browser, TypeScript backend, authenticated realtime and bounded media jobs on port3000. SQLite accounts, configuration, listening state and managed media persist in a private `/data` volume. Original media and import snapshots mount read-only.

The active source is `web/`, `android-native/`, `apple/` and `tvos/`. The obsolete Vue/Nuxt/Capacitor runtime and old backend launch wiring have been removed. Translation catalogs and isolated migration readers remain. Git history preserves the prior application.

- [One-image deployment](web/docs/DEPLOYMENT.md)
- [Complete migration and rollback](docs/fullstack/MIGRATION.md)
- [Backup and recovery](docs/fullstack/RECOVERY.md)
- [Replacement scope and tracked acceptance](docs/fullstack/SPEC.md)
- [Implementation evidence and limits](docs/fullstack/STATE.md)
- [Public release licensing and status](releases/leafwake/README.md)

Install browser/backend dependencies with `npm ci --prefix web`. Root scripts forward to that package. Build the product image with `docker build -t leafwake:local web`; deploy with the environment and volumes described in the deployment guide. Native build instructions live under each native directory. QA uses synthetic data and the replacement image; it never starts the old server or touches an owner's installation.

Audiobook Loft began as an independently maintained fork of the [Audiobookshelf app](https://github.com/advplyr/audiobookshelf-app). Its browser and backend have been rewritten. It is not affiliated with or endorsed by Audiobookshelf. It retains the inherited [GPLv3 license](LICENSE) and applicable dependency notices. Independent branding does not grant additional distribution rights. The initial public Android candidate excludes Chromecast. Apple/TV distribution and Cast exceptions remain subject to the actual licensing assessment and outstanding permission request. A local build or store record is not a published release.
