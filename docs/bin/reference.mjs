#!/usr/bin/env node
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const HEAD = `---
title: "@masks/client"
description: The browser package that signs a single-page app in against masks.
---

The BFF and browser-PKCE halves of \`@masks/client\`, generated from its TypeScript by
\`bin/reference\`. CI fails when this page and the source disagree.

`;

const out = process.argv[2];

if (!out) {
  console.error("usage: bin/reference.mjs <path to the .mdx to write>");
  process.exit(64);
}

const scratch = await mkdtemp(join(tmpdir(), "masks-typedoc-"));

try {
  execFileSync("npx", ["typedoc", "--out", scratch], { stdio: ["ignore", "ignore", "inherit"] });

  const body = await readFile(join(scratch, "browser.mdx"), "utf8");

  await writeFile(out, HEAD + body.replace(/^#\s+.*\n+/, "").trimEnd() + "\n");
} finally {
  await rm(scratch, { recursive: true, force: true });
}
