import { getContext, setContext } from "svelte";

const ROUTER = Symbol("router");

export function createRouter(root) {
  const state = $state({ path: location.pathname });

  addEventListener("popstate", () => {
    state.path = location.pathname;
  });

  return {
    state,

    get segments() {
      return state.path.slice(root.length).split("/").filter(Boolean);
    },

    href(to) {
      return `${root}${to}`;
    },

    go(to) {
      history.pushState({}, "", `${root}${to}`);
      state.path = location.pathname;
      scrollTo({ top: 0 });
    },

    replace(to) {
      history.replaceState({}, "", `${root}${to}`);
      state.path = location.pathname;
    },
  };
}

export function provideRouter(router) {
  setContext(ROUTER, router);
}

export function useRouter() {
  return getContext(ROUTER);
}
