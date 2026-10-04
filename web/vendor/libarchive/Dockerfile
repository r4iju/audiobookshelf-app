FROM emscripten/emsdk:3.1.51@sha256:fde95518821ccc1b629ee674a7a068a809fda47ea16814b0ed53bd646555147b AS build
WORKDIR /build
COPY inputs.json build.sh ./
RUN bash build.sh sources
RUN bash build.sh xz
RUN bash build.sh archive
RUN sed -i 's/-sEXPORT_ES6=1/-sEXPORT_ES6=1 -sENVIRONMENT=worker/' build.sh
RUN bash build.sh wasm
RUN npm install --prefix /build/bundler --ignore-scripts --no-audit --no-fund --force @esbuild/linux-x64@0.25.12
RUN bash build.sh bundle
COPY source-notices.py ./
RUN bash build.sh materials
FROM scratch AS materials
COPY --from=build /output/ /
