const PLACEHOLDER = /%\{(\w+)\}/g;

let held = {};
let plurals = new Intl.PluralRules("en");

export function useCopy(copy, locale = "en") {
  held = copy ?? {};
  plurals = new Intl.PluralRules(locale);
}

function lookup(key) {
  return key
    .split(".")
    .reduce((found, part) => (found == null ? undefined : found[part]), held);
}

function fill(text, values) {
  return text.replace(PLACEHOLDER, (whole, name) =>
    values && Object.hasOwn(values, name) ? String(values[name]) : whole,
  );
}

export function t(key, values) {
  const found = lookup(key);

  if (typeof found === "string") return fill(found, values);

  if (found && typeof found === "object" && values && "count" in values) {
    const form = found[plurals.select(Number(values.count))] ?? found.other;

    if (typeof form === "string") return fill(form, values);
  }

  return key;
}
