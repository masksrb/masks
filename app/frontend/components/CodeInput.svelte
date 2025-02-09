<script>
  import Pincode from "svelte-pincode/unstyled/Pincode.svelte";
  import PincodeInput from "svelte-pincode/unstyled/PincodeInput.svelte";

  /** @type {Props} */
  let {
    auth,
    onComplete,
    length = 7,
    type,
    disabled,
    code = $bindable(),
    value = $bindable(),
    complete = $bindable(),
    class: cls,
    verify,
    ...rest
  } = $props();

  let lastValue;
  let pinClasses = [
    "no-inc py-3 grow w-[100%] input input-bordered px-1.5 md:px-3 text-center join-item font-bold",
  ];

  let classes = $derived([
    ...pinClasses,
    auth?.warnings?.includes(`invalid-code:${value}`) ? "animate-denied" : "",
  ]);

  let handleComplete = (e) => {
    if (!verify || !e.detail.value) {
      return;
    }

    if (e.detail.value !== lastValue) {
      lastValue = e.detail.value.toUpperCase();
      verify(lastValue);
    }
  };
</script>

<Pincode
  {type}
  bind:code
  bind:value
  bind:complete
  class="flex items-center join"
  {disabled}
  on:complete={handleComplete}
>
  {#each { length } as _, i}
    <PincodeInput
      placeholder={type == "numeric" ? "#" : "_"}
      class={[...classes, cls].join(" ")}
    />
  {/each}
</Pincode>
