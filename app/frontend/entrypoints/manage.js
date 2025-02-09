import "./app.css";

import { Router } from "@mateothegreat/svelte5-router";
import { mount } from "svelte";
import App from "@/App.svelte";
import { sentry } from "../sentry.js";

const target = document.getElementById("app");
const props = window.APP || {};

sentry(props.sentry);

let makeRoute = (path, component) => {
  return {
    path,
    component: App,
    props: { ...props, component },
  };
};

mount(Router, {
  props: {
    basepath: "manage",
    routes: [
      makeRoute(
        "client/(.+)",
        async () => import("../manage/ClientPage.svelte")
      ),
      makeRoute("actor/(.+)", async () => import("../manage/ActorPage.svelte")),
      makeRoute(
        "device/(.+)",
        async () => import("../manage/DevicePage.svelte")
      ),
      makeRoute(
        "settings",
        async () => import("../manage/SettingsPage.svelte")
      ),
      makeRoute(
        "/manage/(?<tab>.*)",
        async () => import("../manage/HomePage.svelte")
      ),
      makeRoute("", async () => import("../manage/HomePage.svelte")),
    ],
  },
  target,
});
