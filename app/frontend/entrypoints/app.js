import "./app.css";

import App from "@/App.svelte";
import Component from "@/authenticate/Page.svelte";
import { mount } from "svelte";
import { sentry } from "../sentry.js";

const target = document.getElementById("app");
const props = { ...window.APP, Component };

sentry(props.sentry);

mount(App, {
  target: target,
  props,
});
