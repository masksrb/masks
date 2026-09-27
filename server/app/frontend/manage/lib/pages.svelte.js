export function createPages(size = 25) {
  const state = $state({ cursors: [null], total: null });

  return {
    size,
    state,

    get cursor() {
      return state.cursors.at(-1);
    },

    get first() {
      return (state.cursors.length - 1) * size + 1;
    },

    reset() {
      state.cursors = [null];
    },

    forward(cursor) {
      state.cursors = [...state.cursors, cursor];
    },

    back() {
      if (state.cursors.length > 1) state.cursors = state.cursors.slice(0, -1);
    },

    counted(total) {
      state.total = total;
    },
  };
}
