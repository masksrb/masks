import { mount } from "svelte";
import Login from "../Login.svelte";

const target = document.getElementById("login");

if (target) {
  const auth = JSON.parse(target.dataset.auth);

  target.replaceChildren();

  mount(Login, { target, props: { auth } });
}
