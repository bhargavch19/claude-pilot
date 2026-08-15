#!/usr/bin/env node
// Pilot self-heal: collapse duplicate hook entries in ~/.claude/settings.json.
// GSD/pilot installers append hooks without dedup; over many runs this bloats
// settings.json to tens of MB (observed: 65k PreToolUse entries, 17 unique),
// slowing every tool call. Runs at SessionStart. Safe by construction:
//   - parses first; bails on any parse error
//   - only rewrites if the deduped form is STRICTLY smaller
//   - atomic write (temp + rename); one daily backup
//   - never throws — always exits 0 so it can't block a session.
import { readFileSync, writeFileSync, renameSync, copyFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

try {
  const file = join(homedir(), ".claude", "settings.json");
  if (!existsSync(file)) process.exit(0);

  const raw = readFileSync(file, "utf8");
  const cfg = JSON.parse(raw); // throws → caught → no-op
  if (!cfg || typeof cfg.hooks !== "object" || cfg.hooks === null) process.exit(0);

  let before = 0;
  let after = 0;
  for (const event of Object.keys(cfg.hooks)) {
    const arr = cfg.hooks[event];
    if (!Array.isArray(arr)) continue;
    before += arr.length;
    const seen = new Set();
    const unique = [];
    for (const entry of arr) {
      const key = JSON.stringify(entry);
      if (seen.has(key)) continue;
      seen.add(key);
      unique.push(entry);
    }
    cfg.hooks[event] = unique;
    after += unique.length;
  }

  if (after >= before) process.exit(0); // nothing duplicated → leave file untouched

  // Back up once per day before the first rewrite of the day.
  const stamp = new Date().toISOString().slice(0, 10);
  const bak = `${file}.dedupe-bak.${stamp}`;
  if (!existsSync(bak)) {
    try { copyFileSync(file, bak); } catch { /* best-effort */ }
  }

  const tmp = `${file}.tmp.${process.pid}`;
  writeFileSync(tmp, JSON.stringify(cfg, null, 2) + "\n");
  renameSync(tmp, file);

  process.stdout.write(
    `pilot: deduped settings.json hooks (${before} → ${after} entries).\n`
  );
} catch {
  // Never let self-heal break a session.
}
process.exit(0);
