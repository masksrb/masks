import "./app.css";

import App from "@/App.svelte";
import Component from "@/login/Page.svelte";
import { mount } from "svelte";
import { sentry } from "../sentry.js";

const target = document.getElementById("login");
const props = { ...window.LOGIN, Component };

sentry(props.sentry);

mount(App, {
  target: target,
  props,
});
