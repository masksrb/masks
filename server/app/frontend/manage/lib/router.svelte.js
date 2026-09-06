import { getContext, setContext } from "svelte";

const ROUTER = Symbol("router");

export function createRouter(root) {
  const state = $state({ path: location.pathname, search: location.search });

  const settle = () => {
    state.path = location.pathname;
    state.search = location.search;
  };

  addEventListener("popstate", settle);

  return {
    state,

    get segments() {
      return state.path.slice(root.length).split("/").filter(Boolean);
    },

    get query() {
      return new URLSearchParams(state.search);
    },

    href(to) {
      return `${root}${to}`;
    },

    go(to) {
      history.pushState({}, "", `${root}${to}`);
      settle();
      scrollTo({ top: 0 });
    },

    replace(to) {
      history.replaceState({}, "", `${root}${to}`);
      settle();
    },
  };
}

export function provideRouter(router) {
  setContext(ROUTER, router);
}

export function useRouter() {
  return getContext(ROUTER);
}
