<script>
  import { t } from "../lib/copy.js";
  let { value = $bindable(""), placeholder, label, onsearch } = $props();
</script>

<div class="join w-full sm:w-auto">
  <input
    class="input input-sm join-item w-full sm:w-48 md:w-56"
    type="search"
    aria-label={label}
    {placeholder}
    bind:value
    onkeydown={(event) => event.key === "Enter" && onsearch()}
  />
  <button type="button" class="btn btn-sm join-item" onclick={onsearch}>{t("ui.search")}</button>
</div>
