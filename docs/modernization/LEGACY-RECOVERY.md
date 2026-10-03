# Retained legacy client and migration recovery

The maintained root `dev`, `build` and `start` commands now dispatch to `web/`.
Nuxt/Capacitor is an explicit recovery/export path. This retires the maintained fork's
default client entrypoint, not an installed app, its data, or the upstream server's Vue UI.
No old source, `ios/`, `android/`, dependencies, artifacts, license or notices are deleted.

## Pinned recovery snapshot

Keep annotated tag `legacy-nuxt-export-2026-10-03` immutable. It points to
`bbac469a43d23868dbe61931cd9b013c36554ab3`, immediately before this retirement.
GitHub ruleset `24398277` actively prevents updates and deletion of this exact tag.
Never move or force-push it. Verify the peeled commit before use; the full commit
is the immutable content identity even if a remote tag is changed.
The `upstream` remote remains `https://github.com/advplyr/audiobookshelf-app.git`;
the imported upstream baseline is `7014e04e`. `LICENSE` remains GPL-3.0 and existing
engine notices remain beside their assets.

Restore into a **new** SSD worktree. Do not reset or overwrite the owner's checkout:

```sh
git fetch origin tag legacy-nuxt-export-2026-10-03
git rev-parse 'legacy-nuxt-export-2026-10-03^{commit}'
git worktree add --detach /Volumes/ai-ssd/code/abs-legacy-recovery legacy-nuxt-export-2026-10-03
```

The tagged snapshot retains the original script names (`dev`, `generate`, `sync`).
On the current branch, recovery commands are explicitly prefixed:

```sh
npm ci
npm run legacy:dev
npm run legacy:generate
npm run legacy:sync
npm run legacy:open-ios
# or npm run legacy:open-android
```

Root dependency installation is only needed for this legacy path; normal browser use installs
`web/` dependencies. Preserve the legacy lockfile. Native recovery uses the existing local
SDK/toolchain and signing setup. Root coordinates any packaging or installation.
Do not use these commands in the dirty owner checkout: generation/sync can change its
generated native assets. Opening a project is not authorization to replace an upstream app.

## Export, import and reauthentication

The fork's native legacy Settings route still includes `SettingsLegacyMigrationExport`
(`pages/settings.vue` and `components/settings/LegacyMigrationExport.vue`).
Use that route to write a credential-free migration archive from copies of the legacy
database and media. Keep the archive and the original legacy app/data.
Never rewrite an unknown stored path, delete legacy records or discard unsent progress
to make an import succeed.

Use the maintained native migration-import UI, inspect its preflight and sign in again
to the same server/account before attaching imported records. Passwords, tokens and
custom authentication headers are not transferred. Unknown snapshot fields, history,
settings, files and locations must remain retained even when they cannot be attached.
The importer may stage copies and report missing media; those reports are not proof
of readable content or completed playback migration.

The implemented contracts and production-shaped synthetic evidence remain in
[Apple migration](APPLE-MIGRATION.md), [Apple adoption](APPLE-MIGRATION-ADOPTION.md),
[Android preservation](ANDROID-MIGRATION-PRESERVATION.md) and
[Android runtime](ANDROID-MIGRATION-RUNTIME.md). Read their limitations before cutover.
The public upstream app cannot run this fork-only exporter; its private sandbox cannot
be assumed accessible. Keep it available for its unsent/local history and normal sync.
An in-place replacement needs the owner's identity/signing setup and a validated storage
migration; this entrypoint change does not provide that approval.

## Rollback and hosted workflows

Keep the old installed client, its private data, export and signing material until
validated migration and rollback. Returning to it leaves local legacy data unchanged;
server progress already submitted by a new client is shared state and is not automatically
undone. Do not uninstall/clear either app as an import-error recovery step.

For browser rollback, root retains the currently deployed `bbac469a` image
(`9cde1a07`) and the pinned server rollback. This PR does not deploy, replace that
image, change server/nginx or mutate owner data. Follow [DEPLOYMENT](../../web/docs/DEPLOYMENT.md)
for selecting the retained image; browser local settings and unsent progress stay in place.

Legacy APK/iOS/publish/i18n hosted workflows are archived under
`.github/legacy-workflows/*.disabled` outside the executable workflow directory.
The corresponding GitHub workflows were disabled before pushing the recovery tag.
Their archived original content is preserved as reference. Build/package/sign locally;
do not re-enable those hosted jobs by copying them back without a deliberate scope change.
Issue housekeeping and conditional translation-credit workflows remain unchanged.

Physical device/VoiceOver/native-speaker and real-owner migration/cutover evidence is
deferred where setup is unavailable. Software migration correctness, translation quality
and cutover safety remain required; synthetic results do not substitute for owner approval.
