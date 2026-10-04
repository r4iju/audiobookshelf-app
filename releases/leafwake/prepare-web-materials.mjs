// Public build inputs only. Account state, signing credentials and media are never read.
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';

const output = process.argv[2];
if (!output) throw Error('Usage: node releases/leafwake/prepare-web-materials.mjs OUTPUT');
const root = new URL('../../', import.meta.url);
const lockPath = process.argv[3] ?? new URL('web/package-lock.json', root);
const lockName = process.argv[3] ? basename(process.argv[3]) : 'package-lock.json';
const lock = JSON.parse(await readFile(lockPath, 'utf8'));
const directory = resolve(output);
await mkdir(`${directory}/npm`, { recursive: true });
const unique = [...new Map(Object.values(lock.packages).filter(p => p.resolved && p.integrity).map(p => [p.resolved, p])).values()];
const results = [];
let cursor = 0;
await Promise.all(Array.from({length: 4}, async () => {
  while (cursor < unique.length) {
    const entry = unique[cursor++];
    const url = new URL(entry.resolved);
    if (url.protocol !== 'https:' || url.hostname !== 'registry.npmjs.org') throw Error(`Unreviewed registry ${url.hostname}`);
    const file = `npm/${createHash('sha256').update(entry.resolved).digest('hex')}.tgz`;
    let bytes;
    try { bytes = await readFile(`${directory}/${file}`); } catch {
      const response = await fetch(url, { signal: AbortSignal.timeout(120000) });
      if (!response.ok) throw Error(`${url.pathname}: ${response.status}`);
      bytes = Buffer.from(await response.arrayBuffer());
    }
    const valid = entry.integrity.split(/\s+/).some(sri => {
      const [algorithm, expected] = sri.split('-');
      if (!['sha512', 'sha256', 'sha1'].includes(algorithm)) return false;
      return createHash(algorithm).update(bytes).digest('base64') === expected;
    });
    if (!valid) throw Error(`Integrity mismatch ${url.pathname}`);
    await writeFile(`${directory}/${file}`, bytes);
    results.push({url:entry.resolved,version:entry.version,license:entry.license ?? null,integrity:entry.integrity,file,sha256:createHash('sha256').update(bytes).digest('hex')});
  }
}));
results.sort((a,b) => a.url.localeCompare(b.url));
await writeFile(`${directory}/${process.argv[3] ? lockName.replace('.json', '-inputs.json') : 'npm-inputs.json'}`, JSON.stringify(results,null,2)+'\n');
await writeFile(`${directory}/${lockName}`, JSON.stringify(lock,null,2)+'\n');
console.log(`Verified ${results.length} exact npm inputs, including build and optional-platform packages.`);
