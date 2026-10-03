Bundled reader engines reuse the browser and legacy clients' pinned engines, without CDN access:

- EPUB.js 0.3.88, BSD-2-Clause, `EPUBJS-LICENSE`.
- JSZip 3.10.1, MIT/GPL dual license (used under MIT), `JSZIP-LICENSE`.
- Foliate.js 1.0.1 MOBI/KF8 parser, MIT, `foliate/LICENSE`.
- Foliate's fflate 0.8.2 decompressor, MIT, `foliate/vendor/FFLATE-LICENSE` (upstream v0.8.2 notice).
- libarchive.js 2.0.2, MIT, `libarchive/LICENSE`; the distributed WASM is the package’s libarchive 3.7.2 build (`LIBARCHIVE-COPYING`).

Engine sources are copied from the existing local dependency caches; `reader.js` and `index.html` are the Android host. Book frames cannot run scripts. All document/asset requests stay inside the intercepted local origin; native authenticated downloads supply document bytes. No DRM removal is implemented.
