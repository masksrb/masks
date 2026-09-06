const PLACEHOLDER = /%\{(\w+)\}/g;

export function interpolate(text, values) {
  if (!values) return text;

  return text.replace(PLACEHOLDER, (whole, name) =>
    Object.hasOwn(values, name) ? String(values[name]) : whole,
  );
}

export function translator(source) {
  return (key, values) => {
    const found = source()?.[key];

    return typeof found === "string" ? interpolate(found, values) : "";
  };
}
