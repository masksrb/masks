export function createFeedback() {
  const state = $state({ notice: null, failure: null });

  const clear = () => {
    state.notice = null;
    state.failure = null;
  };

  const blame = (thrown) => {
    state.notice = null;
    state.failure = thrown?.message ?? String(thrown);
  };

  return {
    state,
    clear,
    blame,

    say(notice) {
      state.failure = null;
      state.notice = notice;
    },

    async attempt(work, notice = null) {
      clear();

      try {
        const answer = (await work()) ?? true;

        if (notice) state.notice = notice;

        return answer;
      } catch (thrown) {
        blame(thrown);

        return null;
      }
    },
  };
}
