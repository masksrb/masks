import { mount } from "svelte";
import Person from "../shared/Person.svelte";

document.querySelectorAll(".person-mount[data-person]").forEach((target) => {
  const person = JSON.parse(target.dataset.person);
  const signOut = target.dataset.signOut || null;

  target.replaceChildren();
  mount(Person, { target, props: { person, signOut } });
});
