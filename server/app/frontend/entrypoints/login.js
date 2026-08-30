import { mount } from "svelte";
import Login from "../Login.svelte";

const target = document.getElementById("login");

if (target) {
  mount(Login, {
    target,
    props: { auth: JSON.parse(target.dataset.auth) },
  });
}
