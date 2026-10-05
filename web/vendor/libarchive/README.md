# Comic decoder build materials

The npm libarchive.js 2.0.2 decoder links OpenSSL 1.0.2s. Audiobook Loft serves this independently rebuilt decoder without OpenSSL or Nettle. Password-encrypted comic archives are not a supported release feature. The unchanged public JavaScript client calls the rebuilt worker through Comlink.

The build pins Emscripten 3.1.51 by image digest, libarchivejs commit `0989c1a6db20d030d793b1763e20d880068091bd`, libarchive 3.7.2, xz/liblzma 5.2.11 and source archive SHA256 values. Emscripten supplies zlib 1.2.13 and bzip2 1.0.6 port. Their full inputs and notices accompany the release. The worker targets the browser worker environment and replaces the retired Emscripten allocation helper with the exported UTF-8/malloc interface. Comlink 4.4.1 and esbuild 0.25.12 are pinned; the generated bundler lock and exact npm archives accompany the release.

Rebuild on Linux amd64, or with Docker's supported amd64 emulation:

```sh
docker build --platform linux/amd64 --output type=local,dest=/tmp/leafwake-comic-output web/vendor/libarchive
```

`provenance.json` records the input and output hashes. `scripts/copy-libarchive.mjs` rejects a mismatch before serving either binary. The product image removes the old npm WebAssembly files, serves only this worker/binary, and includes `NOTICES.txt` in its public dependency notice file. The release source bundle contains the upstream archives, Emscripten port sources and the bundler lock. Build outputs in this directory are checked release assets, not another backend or service.

The license check was written and observed failing against the npm decoder before this rebuild. CBZ and CBR reader journeys must both pass against the resulting production image.
