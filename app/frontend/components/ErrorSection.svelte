<script>
  let { code } = $props();

  let codes = {
    404: "404 not found",
  };

  let desc = {
    404: "the requested page does not exist...",
  };
</script>

<div class="flex h-full w-full align-items-center items-center">
  <div class="bold bg-base-300 rounded-lg w-prose mx-auto p-10">
    <h1 class="text-error text-2xl font-bold">
      {codes[code]}
    </h1>

    <h2 class="text-lg">
      {desc[code]}
    </h2>
  </div>
</div>
