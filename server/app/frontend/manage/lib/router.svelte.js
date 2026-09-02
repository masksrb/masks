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

    go(to) {
      history.pushState({}, "", `${root}${to}`);
      state.path = location.pathname;
    },

    replace(to) {
      history.replaceState({}, "", `${root}${to}`);
      state.path = location.pathname;
    },
  };
}
