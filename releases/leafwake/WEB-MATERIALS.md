# Unified image release materials

Publish a versioned source archive and dependency materials alongside each downloadable image. Freeze the reviewed Git revision first. A local development tag is not a published release or an owner's live cutover.

The release manifest records the exact Git revision, architecture, image ID, Docker base digest, runtime-input URL/hash, decoder provenance, artifact hashes and acceptance evidence. Preserve the GPL license, inherited notices and dependency notices. Publish these materials without accounts, media, private configuration, signing keys or credential files.

## Build inputs

- `git archive <revision>` supplies Leafwake source, native source, build recipes, checked comic decoder assets, migration readers and licenses.
- `node releases/leafwake/prepare-web-materials.mjs <output>` downloads the lockfile's exact npm archives and verifies their integrity. Run it again with the decoder build's bundler lockfile as the second argument. The output manifests identify every archive.
- Rebuild the comic worker with `web/vendor/libarchive/Dockerfile`. Its output includes the upstream archive descriptors, decoder hashes, bundler lock and Emscripten zlib/bzip2 port sources. Retain the three input source archives identified in `inputs.json` as well as these outputs.
- Retain the exact Node source and official SHA256 manifest, plus the exact Next.js source tag. The npm package archives also contain Next's distributed compiled code and notices.
- Collect the image's Debian binary/source inventory with `dpkg-query -W -f='${binary:Package}\t${source:Package}\t${source:Version}\n'`. Download every unique source package at that exact version using `apt-get source --download-only package=version`. Enable `deb-src` for the same Debian repositories. If an exact version has left the mirror, use Debian's immutable snapshot archive. Verify all `Checksums-Sha256` entries in every source descriptor; an inventory alone is not source availability.
- Archive the exact added or upgraded `.deb` packages relative to the pinned Node base, with their binary versions and SHA256 hashes. This supplies the reproducible FFmpeg runtime package closure, including its dependencies. Do not include the running installation's `/data` volume.

The runtime-input archive contains a top-level `debs/` directory and its package/hash manifests. Publish it on the same release, then build from the frozen source:

```sh
docker build --platform linux/arm64 \
  --build-arg LEAFWAKE_REVISION=<40-character-revision> \
  --build-arg LEAFWAKE_RUNTIME_INPUTS_URL=<public-https-release-asset> \
  --build-arg LEAFWAKE_RUNTIME_INPUTS_SHA256=<64-character-sha256> \
  -t leafwake:<version> web
```

The installer verifies the whole archive before installing its exact packages. The default local build uses current Debian package indexes; it does not promise to reproduce a previously published package set. The release build uses archived inputs. Compiler timestamps and generated Next build identifiers can still change output bytes; no bit-identical rebuild claim is made.

## Artifact verification and publication

Verify the image's revision, architecture, Debian inventory, FFmpeg configuration, public GPL/dependency notices and decoder hashes. Run the production HTTP/realtime and browser/native journeys against that image. Record physical-device and live migration gates separately from simulator evidence.

Publish the corresponding source/material archives, checksums and notices with the image. A Docker save archive is a valid downloadable image when registry push credentials are unavailable; document `docker load` and its resulting tag. Keep the artifacts versioned rather than silently replacing a tested release. Build other architectures separately and verify them before claiming support.

The one-service deployment, persistent mounts, bootstrap and ingress are documented in [DEPLOYMENT.md](../../web/docs/DEPLOYMENT.md). Current contracts and unverified gates are in [COMPATIBILITY.md](../../docs/fullstack/COMPATIBILITY.md).
