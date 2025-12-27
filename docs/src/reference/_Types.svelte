<script>
import Settings from "./_Settings.svelte";
let props = $props();
</script>

<div class="">
  {#each Object.entries(props.types || {}) as [name, conf]}
    <h3 id={`${name}-settings`}>
      <span class="font-mono">{name}</span> settings
    </h3>

    <Settings settings={conf.settings} id={name} />
  {/each}
</div>
