<script>
  import { t } from "./lib/copy.js";
  let { value = [], available = [], onchange, disabled = false } = $props();

  const SHOWN = 40;
  const FOLDED = 24;
  const id = `scopes-${Math.random().toString(36).slice(2, 10)}`;

  let query = $state("");
  let open = $state(false);
  let active = $state(0);
  let unfolded = $state(false);

  const held = $derived([...new Set(value)].sort());
  const needle = $derived(query.trim().toLowerCase());
  const offered = $derived(
    [...new Set(available)]
      .filter((scope) => !value.includes(scope) && (!needle || scope.toLowerCase().includes(needle)))
      .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b)),
  );
  const listed = $derived(offered.slice(0, SHOWN));
  const typed = $derived(query.trim());
  const novel = $derived(typed !== "" && !value.includes(typed) && !available.includes(typed));
  const choices = $derived(novel ? [...listed, typed] : listed);
  const shown = $derived(unfolded || held.length <= FOLDED ? held : held.slice(0, FOLDED));

  $effect(() => {
    if (active >= choices.length) active = Math.max(choices.length - 1, 0);
  });

  function rank(scope) {
    return needle && scope.toLowerCase().startsWith(needle) ? 0 : 1;
  }

  function add(scope) {
    if (!scope || value.includes(scope)) return;

    onchange([...value, scope]);
    query = "";
    active = 0;
  }

  function remove(scope) {
    onchange(value.filter((one) => one !== scope));
  }

  function keydown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      open = true;
      active = Math.min(active + 1, choices.length - 1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      active = Math.max(active - 1, 0);
    } else if (event.key === "Enter") {
      event.preventDefault();
      add(open && choices.length ? choices[active] : typed);
    } else if (event.key === "Escape") {
      open = false;
    }
  }
</script>

<div class="scope-picker">
  {#if !disabled}
    <div class="scope-picker-field">
      <input
        class="input input-sm w-full font-mono"
        role="combobox"
        aria-expanded={open && choices.length > 0}
        aria-controls={`${id}-list`}
        aria-autocomplete="list"
        aria-activedescendant={open && choices.length ? `${id}-${active}` : undefined}
        aria-label={t("scopes_editor.label")}
        placeholder={t("scopes_editor.placeholder", { count: available.length })}
        autocapitalize="none"
        autocorrect="off"
        spellcheck="false"
        bind:value={query}
        oninput={() => {
          open = true;
          active = 0;
        }}
        onfocus={() => (open = true)}
        onblur={() => (open = false)}
        onkeydown={keydown}
      />

      {#if open && choices.length}
        <ul class="scope-picker-list" id={`${id}-list`} role="listbox" aria-label={t("scopes_editor.offered")}>
          {#each choices as scope, index (scope)}
            <li
              id={`${id}-${index}`}
              role="option"
              aria-selected={index === active}
              class="scope-picker-option"
              class:scope-picker-active={index === active}
              onmousedown={(event) => {
                event.preventDefault();
                add(scope);
              }}
              onmousemove={() => (active = index)}
            >
              {#if novel && index === choices.length - 1}
                <span class="scope-picker-new">{t("scopes_editor.add_new")}</span>
              {/if}
              <span class="scope font-mono" class:scope-privileged={scope.startsWith("masks:")}>{scope}</span>
            </li>
          {/each}

          {#if offered.length > SHOWN}
            <li class="scope-picker-more" role="presentation">
              {t("scopes_editor.more", { count: offered.length - SHOWN })}
            </li>
          {/if}
        </ul>
      {/if}
    </div>
  {/if}

  {#if held.length}
    <ul class="scope-picker-held" aria-label={t("scopes_editor.held", { count: held.length })}>
      {#each shown as scope (scope)}
        <li class="badge font-mono text-xs {scope.startsWith('masks:') ? 'badge-error badge-soft' : 'badge-neutral badge-soft'}">
          {scope}
          {#if !disabled}
            <button
              type="button"
              class="scope-picker-remove"
              aria-label={t("scopes_editor.remove", { scope })}
              onclick={() => remove(scope)}
            >×</button>
          {/if}
        </li>
      {/each}

      {#if held.length > FOLDED}
        <li>
          <button type="button" class="btn btn-ghost btn-xs" onclick={() => (unfolded = !unfolded)}>
            {unfolded ? t("scopes_editor.fewer") : t("scopes_editor.all", { count: held.length })}
          </button>
        </li>
      {/if}
    </ul>
  {:else}
    <p class="hint">{t("scopes_editor.none")}</p>
  {/if}
</div>
