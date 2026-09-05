const CONSEQUENTIAL =
  /(:write|:command|:exec|:delete|:admin)$|^offline_access$/;

export function consequential(scope) {
  return CONSEQUENTIAL.test(String(scope));
}

export function ranked(scopes) {
  const hot = [];
  const rest = [];

  for (const entry of scopes ?? []) {
    (consequential(entry[0]) ? hot : rest).push(entry);
  }

  return { hot, rest };
}
