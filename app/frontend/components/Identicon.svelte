<script>
  import { minidenticon } from "minidenticons";
  /** @type {{ [key: string]: any }} */
  let { ...props } = $props();

  let { id, saturation = 95, lightness = 45, ...others } = props;

  let svgURI = $derived(
    id
      ? "data:image/svg+xml;utf8," +
          encodeURIComponent(minidenticon(id, saturation, lightness))
      : null
  );
</script>

{#if svgURI}
  <img src={svgURI} {...others} alt={`identicon id #${id}`} />
{/if}
