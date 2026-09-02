import { mount } from "svelte";
import App from "../manage/App.svelte";

const target = document.getElementById("manage");

if (target) {
  const boot = JSON.parse(target.dataset.boot);

  target.replaceChildren();

  mount(App, { target, props: { boot } });
}
