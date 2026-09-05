export const NONE = "—";

const DAY = new Intl.DateTimeFormat(undefined, {
  day: "numeric",
  month: "short",
  year: "numeric",
});

const MOMENT = new Intl.DateTimeFormat(undefined, {
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit",
});

const RELATIVE = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });

const STEPS = [
  ["year", 31536000000],
  ["month", 2592000000],
  ["week", 604800000],
  ["day", 86400000],
  ["hour", 3600000],
  ["minute", 60000],
];

function parsed(iso) {
  if (!iso) return null;

  const at = new Date(iso);

  return Number.isNaN(at.getTime()) ? null : at;
}

export function day(iso, fallback = NONE) {
  const at = parsed(iso);

  return at ? DAY.format(at) : fallback;
}

export function moment(iso, fallback = NONE) {
  const at = parsed(iso);

  return at ? MOMENT.format(at) : fallback;
}

export function since(iso, fallback = NONE) {
  const at = parsed(iso);

  if (!at) return fallback;

  const gap = at.getTime() - Date.now();

  for (const [unit, size] of STEPS) {
    if (Math.abs(gap) >= size) {
      return RELATIVE.format(Math.round(gap / size), unit);
    }
  }

  return RELATIVE.format(Math.round(gap / 1000), "second");
}

export function joined(values, fallback = NONE) {
  const kept = (values ?? []).filter(Boolean);

  return kept.length ? kept.join(" ") : fallback;
}
