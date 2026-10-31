#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(import.meta.dirname, "..", "..");
const MANIFEST = join(ROOT, "docs/parity.json");
const PAGE = join(ROOT, "docs/src/content/docs/build/connecting-via-sdk.mdx");
const START = "{/* parity:start */}";
const END = "{/* parity:end */}";
const BLOB = "https://github.com/masksrb/masks/blob/main";

const { sdks, features } = JSON.parse(readFileSync(MANIFEST, "utf8"));

const problems = [];
const notes = [];

function declared(file, name) {
  const forms = [`test "${name}"`, `def ${name}`, `test("${name}"`, `test(\`${name}\``, `func ${name}(`];
  const lines = file.split("\n");
  const index = lines.findIndex((line) => forms.some((form) => line.includes(form)));

  return index === -1 ? undefined : index + 1;
}

function prove(feature, sdk, cell) {
  let body;

  try {
    body = readFileSync(join(ROOT, cell.file), "utf8");
  } catch {
    problems.push(`${feature} for ${sdk.label} names ${cell.file}, which does not exist`);
    return undefined;
  }

  const line = declared(body, cell.test);

  if (!line) problems.push(`${feature} for ${sdk.label} names a test ${cell.file} does not declare: ${cell.test}`);

  return line;
}

function escape(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("{", "&#123;")
    .replaceAll("}", "&#125;");
}

function inline(text) {
  return escape(text).replace(/`([^`]+)`/g, "<code>$1</code>");
}

function noted(note) {
  let index = notes.indexOf(note);

  if (index === -1) index = notes.push(note) - 1;

  return index + 1;
}

let proven = 0;
let claimed = 0;

const rows = features.map((feature) => {
  const name = feature.link ? `<a href="${escape(feature.link)}">${inline(feature.name)}</a>` : inline(feature.name);

  const cells = sdks.map((sdk) => {
    const cell = feature.cells[sdk.key];

    if (cell === undefined) {
      problems.push(`${feature.name} has no cell for ${sdk.label}`);
      return "<td></td>";
    }

    if (cell === "no") return `<td class="no"><span title="${escape(`${sdk.label} does not do this`)}">–</span></td>`;

    claimed += 1;

    const mark = cell.note ? `<sup>${noted(cell.note)}</sup>` : "";

    if (cell.claimed) return `<td class="unproven"><span title="Claimed, and no test proves it">?</span>${mark}</td>`;

    const line = prove(feature.name, sdk, cell);

    if (!line) return `<td class="unproven"><span title="Claimed, and no test proves it">?</span>${mark}</td>`;

    proven += 1;

    const title = escape(`${sdk.label}: proven by “${cell.test}” in ${cell.file}`);

    return `<td class="yes"><a href="${BLOB}/${cell.file}#L${line}" title="${title}">✓</a>${mark}</td>`;
  });

  return `<tr><th scope="row">${name}</th>${cells.join("")}</tr>`;
});

const head = sdks
  .map((sdk) => `<th scope="col"><abbr title="${escape(sdk.label)}">${escape(sdk.short)}</abbr></th>`)
  .join("");

const table = [
  `<table class="parity">`,
  `<thead><tr><th scope="col">What the SDK does</th>${head}</tr></thead>`,
  `<tbody>`,
  ...rows,
  `</tbody>`,
  `</table>`,
  ``,
  `<ol class="parity-notes">`,
  ...notes.map((note) => `<li>${inline(note)}</li>`),
  `</ol>`,
  ``,
  `<p class="parity-count">${proven} of ${claimed} cells are proven by a test. Each check mark opens the test.</p>`,
].join("\n");

for (const problem of problems) console.error(problem);

if (problems.length) process.exit(1);

const page = readFileSync(PAGE, "utf8");
const start = page.indexOf(START);
const end = page.indexOf(END);

if (start === -1 || end === -1 || end < start) {
  console.error(`${relative(ROOT, PAGE)} has no ${START} and ${END} region to write the grid into`);
  process.exit(1);
}

writeFileSync(PAGE, `${page.slice(0, start + START.length)}\n\n${table}\n\n${page.slice(end)}`);
