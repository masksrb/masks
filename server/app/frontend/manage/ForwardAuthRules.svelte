<script>
  import { untrack } from "svelte";
  import Section from "./ui/Section.svelte";
  import Select from "./ui/Select.svelte";
  import { t } from "./lib/copy.js";

  let { rules = [], onsave } = $props();

  const OUTCOMES = ["one_factor", "two_factor", "token", "open", "deny"].map((key) => [
    key,
    t(`forward_auth_rules.outcomes.${key}`),
  ]);

  const LISTS = ["paths", "methods", "networks", "groups"];

  const drafted = (held) =>
    held.map((rule) => ({
      ...Object.fromEntries(LISTS.map((list) => [list, (rule[list] ?? []).join(list === "paths" ? "\n" : ", ")])),
      outcome: rule.outcome,
    }));

  let rows = $state(untrack(() => drafted(rules)));

  $effect(() => {
    rows = drafted(rules);
  });

  const split = (value, list) =>
    value
      .split(list === "paths" ? /\n/ : /[\s,]+/)
      .map((one) => one.trim())
      .filter(Boolean);

  const held = () =>
    rows.map((row) => ({
      ...Object.fromEntries(LISTS.map((list) => [list, split(row[list], list)])),
      outcome: row.outcome,
    }));

  function add() {
    rows = [...rows, { paths: "", methods: "", networks: "", groups: "", outcome: "one_factor" }];
  }

  function remove(index) {
    rows = rows.filter((_, at) => at !== index);
  }

  function move(index, by) {
    const next = [...rows];
    [next[index], next[index + by]] = [next[index + by], next[index]];
    rows = next;
  }
</script>

<Section row title={t("forward_auth_rules.title")} lede={t("forward_auth_rules.lede")}>
  {#if rows.length}
    <ol class="flex flex-col gap-4">
      {#each rows as row, index (index)}
        <li class="flex flex-col gap-2 rounded-box border border-base-300 p-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="field-label">{t("forward_auth_rules.rule", { number: index + 1 })}</span>
            <div class="flex gap-1">
              <button type="button" class="btn btn-ghost btn-xs" disabled={index === 0} onclick={() => move(index, -1)}>
                {t("forward_auth_rules.up")}
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                disabled={index === rows.length - 1}
                onclick={() => move(index, 1)}
              >
                {t("forward_auth_rules.down")}
              </button>
              <button type="button" class="btn btn-ghost btn-xs" onclick={() => remove(index)}>
                {t("forward_auth_rules.remove")}
              </button>
            </div>
          </div>

          <label class="flex flex-col gap-1.5">
            <span class="field-label">{t("forward_auth_rules.paths")}</span>
            <textarea
              class="textarea textarea-sm w-full font-mono text-xs"
              rows="2"
              spellcheck="false"
              placeholder="/admin/**"
              bind:value={row.paths}
            ></textarea>
            <span class="hint">{t("forward_auth_rules.paths_hint")}</span>
          </label>

          <div class="grid gap-2 sm:grid-cols-3">
            {#each ["methods", "networks", "groups"] as list (list)}
              <label class="flex min-w-0 flex-col gap-1.5">
                <span class="field-label">{t(`forward_auth_rules.${list}`)}</span>
                <input
                  class="input input-sm w-full font-mono text-xs"
                  autocapitalize="none"
                  autocorrect="off"
                  spellcheck="false"
                  bind:value={row[list]}
                />
                <span class="hint">{t(`forward_auth_rules.${list}_hint`)}</span>
              </label>
            {/each}
          </div>

          <Select
            label={t("forward_auth_rules.outcome")}
            value={row.outcome}
            options={OUTCOMES}
            onchange={(outcome) => (row.outcome = outcome)}
          />
        </li>
      {/each}
    </ol>
  {:else}
    <p class="text-sm opacity-85">{t("forward_auth_rules.empty")}</p>
  {/if}

  <p class="hint">{t("forward_auth_rules.trust")}</p>

  <div class="flex flex-wrap gap-2">
    <button type="button" class="btn btn-sm" onclick={add}>{t("forward_auth_rules.add")}</button>
    <button type="button" class="btn btn-sm btn-primary" onclick={() => onsave(held())}>
      {t("forward_auth_rules.save")}
    </button>
  </div>
</Section>
