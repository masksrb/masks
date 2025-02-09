<script>
  let { value, class: cls, summary, dropdown, ...props } = $props();

  let element;
  let setValue = (v, cb, e) => {
    value = v;

    if (element) {
      element.open = false;
    }

    if (cb) {
      cb(v);
    }
  };

  let open = $state();

  let updateOpen = (e) => {
    e.preventDefault();
    e.stopPropagation();

    open = element?.open;
  };
</script>

<details class={`dropdown ${cls}`} bind:this={element} ontoggle={updateOpen}>
  {@render summary?.({ value, open })}
  <div
    class={`dropdown-content dark:bg-black bg-neutral rounded-lg shadow-xl
      z-20
      ${props.dropdownClass || ""}`}
  >
    {@render dropdown?.({ value, setValue })}
  </div>
</details>
