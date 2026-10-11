import { mount } from "svelte";
import App from "../manage/App.svelte";
import { useCopy } from "../manage/lib/copy.js";

const target = document.getElementById("manage");

if (target) {
  const boot = JSON.parse(target.dataset.boot);

  useCopy(boot.copy, document.documentElement.lang || "en");
  target.replaceChildren();

  mount(App, { target, props: { boot } });
}
