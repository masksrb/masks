#!/usr/bin/env node
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(import.meta.dirname, "..", "..");
const PAGE = join(ROOT, "docs/src/content/docs/reference/environment.mdx");

const SOURCES = [
  { roots: ["server/app", "server/config", "server/lib", "server/bin", "engine/app", "engine/config", "engine/lib", "client/lib", "test", "dev"], files: /(\.(rb|erb|yml|rake|tt)|\/dev)$/, reads: /ENV(?:\.fetch)?[[(]\s*["']([A-Z][A-Z0-9_]*)["']/g },
  { roots: ["server/vite.config.ts", "docs/astro.config.mjs", "web/src"], files: /\.(ts|mjs|js)$/, reads: /process\.env\.([A-Z][A-Z0-9_]*)/g },
  { roots: ["compose.yml", "compose.multi.yml", "compose.test.yml", "compose.test.ci.yml"], files: /\.yml$/, reads: /\$\{([A-Z][A-Z0-9_]*)/g },
];

const SKIPPED = /(^|\/)(node_modules|\.suite|tmp|vendor)(\/|$)/;

const INTERNAL = new Set(["PATH", "BUNDLE_GEMFILE", "DEFAULT_TEST"]);

const DEPENDENCIES = new Set([
  "SECRET_KEY_BASE",
  "HTTP_PORT",
  "TARGET_PORT",
  "TLS_DOMAIN",
  "VITE_RUBY_HOST",
  "VITE_RUBY_SKIP_PROXY",
  "MASKS_MASTER_KEY",
  "MASKS_MASTER_KEY_FILE",
]);

function* walk(path) {
  const full = join(ROOT, path);
  let stat;

  try {
    stat = statSync(full);
  } catch {
    return;
  }

  if (SKIPPED.test(path)) return;

  if (stat.isFile()) {
    yield path;
    return;
  }

  for (const entry of readdirSync(full)) yield* walk(join(path, entry));
}

const read = new Map();

for (const { roots, files, reads } of SOURCES) {
  for (const root of roots) {
    for (const path of walk(root)) {
      if (!files.test(`/${path}`)) continue;

      for (const [, name] of readFileSync(join(ROOT, path), "utf8").matchAll(reads)) {
        if (INTERNAL.has(name)) continue;
        if (!read.has(name)) read.set(name, path);
      }
    }
  }
}

const listed = new Set(
  [...readFileSync(PAGE, "utf8").matchAll(/^\| `([A-Z][A-Z0-9_]*)` \|/gm)].map(([, name]) => name),
);

const unlisted = [...read].filter(([name]) => !listed.has(name));
const unread = [...listed].filter((name) => !read.has(name) && !DEPENDENCIES.has(name));

for (const [name, path] of unlisted) {
  console.error(`${name} is read by ${path} and missing from ${relative(ROOT, PAGE)}`);
}

for (const name of unread) {
  console.error(`${name} is listed in ${relative(ROOT, PAGE)} and read by nothing`);
}

if (unlisted.length || unread.length) process.exit(1);
