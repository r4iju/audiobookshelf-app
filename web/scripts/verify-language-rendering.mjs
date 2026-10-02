import assert from "node:assert/strict";

const origin = process.argv[2];
assert(origin, "Pass the locally running client origin");
for (const [code, lang, dir, heading] of [
  ["de", "de", "ltr", "Mit Server verbinden"],
  ["ar", "ar", "rtl", "اتصال بالخادم"],
  ["invalid", "en-US", "ltr", "Connect to Server"],
]) {
  const response = await fetch(`${origin}/connect`, { headers: { Cookie: `abs-web-language=${code}` } });
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, new RegExp(`<html[^>]*lang="${lang}"[^>]*dir="${dir}"`));
  assert(html.includes(heading), `${code}: translated initial heading`);
  assert(html.includes(`<title>${heading} · Audiobookshelf</title>`), `${code}: translated metadata`);
  console.log(`${code}: initial language, direction, heading and title passed`);
}
