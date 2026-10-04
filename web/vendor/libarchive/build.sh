#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == sources ]]; then
python3 - <<'PY'
import json,hashlib,urllib.request,tarfile
for item in json.load(open('inputs.json')):
    data=urllib.request.urlopen(item['url']).read()
    assert hashlib.sha256(data).hexdigest()==item['sha256'], item['name']
    open(item['name'],'wb').write(data)
    with tarfile.open(item['name']) as archive: archive.extractall('.',filter='data')
PY
fi
if [[ $1 == xz ]]; then
cd /build/xz-5.2.11
emconfigure ./configure --disable-assembler --enable-threads=no --enable-static=yes --disable-shared --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-lzma-links --disable-scripts
emmake make -j4
emmake make install
fi
if [[ $1 == archive ]]; then
cd /build/libarchive-3.7.2
EMCC_CFLAGS='-sUSE_ZLIB=1 -sUSE_BZIP2=1' emconfigure ./configure --enable-static --disable-shared --disable-bsdtar --disable-bsdcat --disable-bsdcpio --without-openssl --without-nettle --without-lzo2 --without-cng --without-lz4 --without-xml2 --without-expat --disable-xattr --disable-acl
EMCC_CFLAGS='-sUSE_ZLIB=1 -sUSE_BZIP2=1' emmake make -j4
emmake make install
fi
cd /build/libarchivejs-0989c1a6db20d030d793b1763e20d880068091bd
if [[ $1 == wasm ]]; then
emcc lib/wrapper/main.c /usr/local/lib/libarchive.a /usr/local/lib/liblzma.a -I/usr/local/include -o src/webworker/wasm-gen/libarchive.js -sUSE_ZLIB=1 -sUSE_BZIP2=1 -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=libarchive -O3 -sALLOW_MEMORY_GROWTH=1 -sEXPORTED_RUNTIME_METHODS='["cwrap","lengthBytesUTF8","stringToUTF8"]' -sEXPORTED_FUNCTIONS=@lib/tools/lib.exports
python3 - <<'PY'
p='src/webworker/wasm-module.js'
s=open(p).read().replace('string: (str) => this.allocate(this.intArrayFromString(str), "i8", 0),','string: (str) => { const length = this.lengthBytesUTF8(str) + 1; const pointer = this._malloc(length); this.stringToUTF8(str, pointer, length); return pointer; },')
open(p,'w').write(s)
PY
fi
if [[ $1 == bundle ]]; then
npm install --prefix /build/bundler --ignore-scripts --no-audit --no-fund comlink@4.4.1 esbuild@0.25.12
ln -s /build/bundler/node_modules node_modules
mkdir -p /output
/build/bundler/node_modules/.bin/esbuild src/webworker/browser-worker.js --bundle --format=esm --outfile=/output/worker-bundle.js
fi
if [[ $1 == materials ]]; then
cp src/webworker/wasm-gen/libarchive.wasm /output/
cp LICENSE /output/libarchivejs-LICENSE
cp /build/libarchive-3.7.2/COPYING /output/libarchive-COPYING
cp /build/xz-5.2.11/COPYING /output/xz-COPYING
cp /build/bundler/package-lock.json /output/bundler-package-lock.json
cp /build/bundler/node_modules/comlink/LICENSE /output/comlink-LICENSE
for source in /emsdk/upstream/emscripten/LICENSE /emsdk/upstream/emscripten/system/lib/libc/musl/COPYRIGHT /emsdk/upstream/emscripten/system/lib/compiler-rt/LICENSE.TXT; do
  basename "$source"
  cat "$source"
done > /output/emscripten-NOTICES.txt
mkdir -p /output/ports
cp -R /emsdk/upstream/emscripten/cache/ports/zlib* /emsdk/upstream/emscripten/cache/ports/bzip2* /output/ports
python3 /build/source-notices.py /build /output/source-file-notices.txt
python3 - <<'PY'
import json,hashlib,pathlib
out=pathlib.Path('/output')
assert b'OpenSSL' not in (out/'libarchive.wasm').read_bytes()
p={'sourceSha':'0989c1a6db20d030d793b1763e20d880068091bd','emsdkImage':'emscripten/emsdk:3.1.51@sha256:fde95518821ccc1b629ee674a7a068a809fda47ea16814b0ed53bd646555147b','openssl':False,'inputs':json.load(open('/build/inputs.json')),'artifacts':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in out.iterdir() if f.is_file()}}
(out/'provenance.json').write_text(json.dumps(p,indent=2)+'\n')
PY
fi
