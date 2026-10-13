import { flushSync, mount } from "svelte";
import Login from "../Login.svelte";
import { heldInputs, restoreInputs } from "../lib/typed.js";

const target = document.getElementById("login");

if (target) {
  const auth = JSON.parse(target.dataset.auth);
  const held = heldInputs(target);

  target.replaceChildren();

  mount(Login, { target, props: { auth } });
  flushSync();
  restoreInputs(target, held);
}
