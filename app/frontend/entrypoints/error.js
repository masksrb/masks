import "./app.css";

import App from "@/App.svelte";
import Component from "@/error/Page.svelte";
import { mount } from "svelte";

const target = document.getElementById("app");
const props = { ...window.APP, Component };

mount(App, {
  target: target,
  props,
});
