export const initial = (name) => (name ?? "").trim().slice(0, 1).toUpperCase();

export const initials = (name) =>
  (name ?? "").split(/\s+/).filter(Boolean).slice(0, 2).map(initial).join("");
