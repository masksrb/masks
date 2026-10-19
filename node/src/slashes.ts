export function untrailed(value: string): string {
  let end = value.length;

  while (end > 0 && value[end - 1] === "/") end -= 1;

  return value.slice(0, end);
}

export function unslashed(value: string): string {
  const trailed = untrailed(value);
  let start = 0;

  while (start < trailed.length && trailed[start] === "/") start += 1;

  return trailed.slice(start);
}
