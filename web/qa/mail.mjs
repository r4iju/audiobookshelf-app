// A loopback mail sink for the QA server's "send ebook to device" (which reaches it as host.docker.internal), so
// sending is exercised without any real mail. Each accepted message is written to qa/.runtime/mail; recipients at
// bounce.invalid are refused, which is how a failed delivery is exercised.
//   node qa/mail.mjs
import { mkdirSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const MAIL_PORT = Number(process.env.ABS_QA_MAIL_PORT ?? 19886);
export const mailDir = join(dirname(fileURLToPath(import.meta.url)), ".runtime", "mail");

const server = createServer((socket) => {
  let buffer = "";
  let data = null;
  let envelope = { from: "", to: [] };
  const reply = (line) => socket.write(`${line}\r\n`);
  reply("220 abs-web-qa mail sink");

  socket.on("data", (chunk) => {
    buffer += chunk.toString("latin1");
    for (;;) {
      if (data !== null) {
        const end = buffer.indexOf("\r\n.\r\n");
        if (end === -1) return;
        data += buffer.slice(0, end);
        buffer = buffer.slice(end + 5);
        mkdirSync(mailDir, { recursive: true });
        const name = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        writeFileSync(join(mailDir, `${name}.json`), JSON.stringify({ ...envelope, data }));
        data = null;
        envelope = { from: "", to: [] };
        reply("250 OK");
        continue;
      }
      const end = buffer.indexOf("\r\n");
      if (end === -1) return;
      const line = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      const command = line.slice(0, 4).toUpperCase();
      if (command === "EHLO" || command === "HELO") reply("250 abs-web-qa");
      else if (command === "MAIL") {
        envelope.from = line.replace(/^MAIL FROM:\s*/i, "");
        reply("250 OK");
      } else if (command === "RCPT") {
        const to = line.replace(/^RCPT TO:\s*/i, "");
        if (to.includes("@bounce.invalid")) reply("550 No such mailbox");
        else {
          envelope.to.push(to);
          reply("250 OK");
        }
      } else if (command === "DATA") {
        data = "";
        reply("354 End data with <CR><LF>.<CR><LF>");
      } else if (command === "QUIT") {
        reply("221 Bye");
        socket.end();
      } else if (command === "RSET") {
        envelope = { from: "", to: [] };
        reply("250 OK");
      } else reply("250 OK");
    }
  });
  socket.on("error", () => {});
});

if (process.argv[1] === fileURLToPath(import.meta.url))
  server.listen(MAIL_PORT, process.env.ABS_QA_FIXTURE_HOST ?? "127.0.0.1", () =>
    console.log(`QA mail sink on 127.0.0.1:${MAIL_PORT}`),
  );
