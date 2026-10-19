#!/usr/bin/env node
import { appendFileSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(import.meta.dirname, "..");
const PAGES = join(ROOT, "src/content/docs");
const CEILING = Number(process.env.READABILITY_CEILING ?? 11);
const GENERATED = ["reference/manage", "reference/javascript/client", "reference/ruby/client", "reference/ruby/rails"];

function* walk(path) {
  for (const entry of readdirSync(path)) {
    const full = join(path, entry);

    if (statSync(full).isDirectory()) yield* walk(full);
    else if (/\.mdx?$/.test(entry)) yield full;
  }
}

function prose(source) {
  return source
    .replace(/^---\n[\s\S]*?\n---\n/, "")
    .replace(/```[\s\S]*?```/g, "")
    .replace(/^\|.*$/gm, "")
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/^import .*$/gm, "")
    .replace(/`[^`]*`/g, "code")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/^#+\s*/gm, "")
    .replace(/^\s*[-*]\s+/gm, "")
    .replace(/^\s*\d+\.\s+/gm, "")
    .replace(/[*_]{1,2}/g, "");
}

function syllables(word) {
  const bare = word.toLowerCase().replace(/[^a-z]/g, "");

  if (bare.length <= 3) return bare.length ? 1 : 0;

  const counted = bare
    .replace(/(?:[^laeiouy]es|ed|[^laeiouy]e)$/, "")
    .replace(/^y/, "")
    .match(/[aeiouy]{1,2}/g);

  return Math.max(1, counted ? counted.length : 1);
}

function grade(text) {
  const sentences = text.split(/[.!?]+(?:\s|$)/).filter((s) => s.trim().split(/\s+/).length > 1);
  const words = text.split(/\s+/).filter((w) => /[a-zA-Z]/.test(w));

  if (sentences.length === 0 || words.length === 0) return { grade: 0, words: 0, sentences: 0 };

  const total = words.reduce((sum, word) => sum + syllables(word), 0);
  const value = 0.39 * (words.length / sentences.length) + 11.8 * (total / words.length) - 15.59;

  return { grade: Math.round(value * 10) / 10, words: words.length, sentences: sentences.length };
}

const rows = [...walk(PAGES)]
  .map((file) => {
    const source = readFileSync(file, "utf8");
    const page = relative(PAGES, file).replace(/\.mdx?$/, "");

    if (GENERATED.includes(page) || /^template:\s*splash/m.test(source)) return undefined;

    return { page, ...grade(prose(source)) };
  })
  .filter((row) => row && row.words >= 60)
  .sort((a, b) => b.grade - a.grade);

const grades = rows.map((row) => row.grade).sort((a, b) => a - b);
const median = grades.length ? grades[Math.floor(grades.length / 2)] : 0;
const over = rows.filter((row) => row.grade > CEILING);

const table = [
  "| Page | Grade | Words | Words a sentence |",
  "| --- | ---: | ---: | ---: |",
  ...rows.map((row) => `| ${row.page} | ${row.grade.toFixed(1)} | ${row.words} | ${(row.words / row.sentences).toFixed(1)} |`),
  "",
  `Median grade ${median.toFixed(1)} across ${rows.length} pages. The style guide asks for grade 7; a page over ${CEILING} fails the build. Generated reference pages are left out.`,
].join("\n");

console.log(table);

if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## Reading grade\n\n${table}\n\n`);

if (over.length) {
  console.error(`\n${over.length} page(s) read above grade ${CEILING}: ${over.map((row) => row.page).join(", ")}`);
  process.exit(1);
}
