# Retained dependency license texts

The runtime notice generator also extracts license and NOTICE files from each resolved JAR/AAR and nested classes JAR. These standalone texts supply full licenses and upstream MIT copyright notices where artifacts do not embed them.

| File | Retrieved source |
| --- | --- |
| Apache-2.0.txt | https://www.apache.org/licenses/LICENSE-2.0.txt |
| MPL-2.0.txt | https://www.mozilla.org/media/MPL/2.0/index.txt |
| socket.io-client.txt | https://raw.githubusercontent.com/socketio/socket.io-client-java/socket.io-client-2.1.2/LICENSE |
| engine.io-client.txt | https://raw.githubusercontent.com/socketio/engine.io-client-java/engine.io-client-2.1.0/LICENSE |

Retrieved October 4, 2026. Checker Framework qualifier MIT notices are extracted from checker-qual:3.43.0 directly. OkHttp:4.12.0 embeds the MPL notice for its Public Suffix List data; its notice and full MPL text are retained. Preserve access to corresponding dependency sources when distributing the artifact. An inventory of declared POM licenses does not cover every license inside a dependency, which is why embedded notices are retained as well.
