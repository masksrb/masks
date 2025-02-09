<script>
  import _ from "lodash-es";
  import Icon from "@iconify/svelte";

  let {
    children,
    loading,
    disabled,
    event = null,
    label = "Continue",
    denied = false,
    deniedLabel = "Try again",
    updates = {},
    authorize,
    type = "button",
    class: cls,
    ...props
  } = $props();

  let isAuthorizing = $state();
  let onclick = async (e) => {
    if (props.confirm && !confirm(props.confirm)) {
      e?.preventDefault();
      e?.stopPropagation();

      return;
    }

    if (props.onclick) {
      return props.onclick(e);
    }

    if (authorize) {
      e.preventDefault();
      e.stopPropagation();

      isAuthorizing = true;
      let result = await authorize({ event, updates });
      isAuthorizing = false;
      props.onAuthorize?.(result);
    }
  };
</script>

<button
  {...props}
  {type}
  class={`btn btn-lg min-w-[130px] ${cls} text-center ${denied ? "animate-denied" : ""}`}
  disabled={isAuthorizing || loading || disabled}
  {onclick}
>
  {#if isAuthorizing || loading}
    <span class="loading loading-spinner loading-md mx-auto"></span>
  {:else if children}{@render children({ denied })}{:else}
    {#if props.icon}
      {@const Custom = props.icon}
      <Custom class={props.iconClass} />
    {:else if props.iconify}
      <Icon icon={props.iconify} />
    {/if}

    <span class={props.labelClass}>
      {denied ? deniedLabel : label}
    </span>
  {/if}
</button>
