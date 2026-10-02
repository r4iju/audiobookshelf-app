import { execFileSync } from "node:child_process";

export default function globalSetup() {
  execFileSync("node", ["qa/server.mjs", "up"], { stdio: "inherit" });
}
