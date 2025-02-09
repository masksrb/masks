import _ from "lodash-es";
import { writable } from "svelte/store";

export * from "./gql";
export * from "./login";
export * from "./consumer";

export const toasts = writable([]);
export const toast = (message, vars = null) => {
  const toast = _.template(message)(vars);

  setTimeout(() => {
    toasts.update((v) => v.filter((m) => m !== toast));
  }, 5000);

  toasts.update((v) => [...v, toast]);
};
