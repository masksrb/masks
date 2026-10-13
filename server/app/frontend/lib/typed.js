const SKIPPED = new Set(["hidden", "checkbox", "radio", "submit", "button"]);

export function heldInputs(root) {
  return [...root.querySelectorAll("input[name]")]
    .filter((input) => !SKIPPED.has(input.type) && input.value)
    .map((input) => ({
      name: input.name,
      value: input.value,
      focused: input === input.ownerDocument.activeElement,
    }));
}

export function restoreInputs(root, held) {
  for (const { name, value, focused } of held) {
    const input = root.querySelector(`input[name="${CSS.escape(name)}"]`);

    if (!input || SKIPPED.has(input.type) || input.value) continue;

    input.value = value;
    input.dispatchEvent(new Event("input", { bubbles: true }));

    if (focused) input.focus();
  }
}
