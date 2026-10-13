import assert from "node:assert/strict";
import { test } from "node:test";
import { heldInputs, restoreInputs } from "../../app/frontend/lib/typed.js";

globalThis.CSS ??= { escape: (value) => value };

class Input extends EventTarget {
  constructor(document, { name, type = "text", value = "" }) {
    super();
    this.ownerDocument = document;
    this.name = name;
    this.type = type;
    this.value = value;
  }

  focus() {
    this.ownerDocument.activeElement = this;
  }
}

function page(fields) {
  const document = { activeElement: null };
  const inputs = fields.map((field) => new Input(document, field));

  return {
    document,
    inputs,
    querySelectorAll: () => inputs,
    querySelector: (selector) =>
      inputs.find((input) => selector === `input[name="${input.name}"]`),
  };
}

test("what a person typed before the script loaded is carried into the mounted form", () => {
  const server = page([
    { name: "authenticity_token", type: "hidden", value: "csrf" },
    { name: "identifier", value: "ada@example.com" },
    { name: "remember", type: "checkbox", value: "on" },
  ]);
  server.inputs[1].focus();

  const held = heldInputs(server);

  assert.deepEqual(held, [
    { name: "identifier", value: "ada@example.com", focused: true },
  ]);

  const mounted = page([{ name: "identifier" }]);
  const seen = [];
  mounted.inputs[0].addEventListener("input", (event) =>
    seen.push(event.target.value),
  );

  restoreInputs(mounted, held);

  assert.equal(mounted.inputs[0].value, "ada@example.com");
  assert.deepEqual(seen, ["ada@example.com"]);
  assert.equal(mounted.document.activeElement, mounted.inputs[0]);
});

test("a field the mounted form already filled in keeps its own value", () => {
  const mounted = page([{ name: "identifier", value: "grace@example.com" }]);

  restoreInputs(mounted, [
    { name: "identifier", value: "ada@example.com", focused: false },
  ]);

  assert.equal(mounted.inputs[0].value, "grace@example.com");
});

test("a field the mounted form does not have is left behind", () => {
  const mounted = page([{ name: "code" }]);

  restoreInputs(mounted, [
    { name: "identifier", value: "ada@example.com", focused: false },
  ]);

  assert.equal(mounted.inputs[0].value, "");
  assert.equal(mounted.document.activeElement, null);
});
