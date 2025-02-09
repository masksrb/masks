import "./app.css";

import App from "@/App.svelte";
import { mount } from "svelte";
import { sentry } from "../sentry.js";

const target = document.getElementById("app");
const props = { ...window.APP };

sentry(props.sentry);

mount(App, {
  target: target,
  props,
});
