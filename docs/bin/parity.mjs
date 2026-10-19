#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(import.meta.dirname, "..", "..");
const MANIFEST = join(ROOT, "docs/parity.json");
const PAGE = join(ROOT, "docs/src/content/docs/guides/connecting-via-sdk.mdx");
const START = "{/* parity:start */}";
const END = "{/* parity:end */}";
const BLOB = "https://github.com/masksrb/masks/blob/main";

const { sdks, features } = JSON.parse(readFileSync(MANIFEST, "utf8"));

const problems = [];

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

let proven = 0;
let claimed = 0;

const rows = features.map((feature) => {
  const name = feature.link ? `[${feature.name}](${feature.link})` : feature.name;

  const cells = sdks.map((sdk) => {
    const cell = feature.cells[sdk.key];

    if (cell === undefined) {
      problems.push(`${feature.name} has no cell for ${sdk.label}`);
      return "";
    }

    if (cell === "no") return "No";

    claimed += 1;

    if (cell.claimed) return "Unproven";

    const line = prove(feature.name, sdk, cell);

    if (!line) return "Unproven";

    proven += 1;

    return `[${cell.note ?? "Yes"}](${BLOB}/${cell.file}#L${line})`;
  });

  return [name, ...cells];
});

const header = ["", ...sdks.map((sdk) => sdk.label)];
const widths = header.map((_, column) => Math.max(...[header, ...rows].map((row) => row[column].length), 3));
const line = (row) => `| ${row.map((cell, column) => cell.padEnd(widths[column])).join(" | ")} |`;

const table = [
  line(header),
  `| ${widths.map((width) => "-".repeat(width)).join(" | ")} |`,
  ...rows.map(line),
  "",
  `${proven} of ${claimed} cells are proven by a test.`,
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
