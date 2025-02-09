<script>
  import { goto, query } from "@mateothegreat/svelte5-router";
  import Dropdown from "@/components/Dropdown.svelte";
  import {
    Filter,
    X,
    Search,
    ChevronDown,
    ChevronRight,
    ChevronLeft,
    ChevronUp,
  } from "lucide-svelte";

  let { result, refresh, ...props } = $props();

  let goNext = () => {
    if (result?.pageInfo?.hasNextPage) {
      refresh({ after: result.pageInfo.endCursor });
    }
  };

  let goPrevious = () => {
    if (result?.pageInfo?.hasPreviousPage) {
      refresh({ before: result.pageInfo.startCursor });
    }
  };
</script>

<div class={`flex items-center gap-2 ${props.class}`}>
  <p class="text-neutral-content font-bold text-base grow">
    {props.label || "Records"}
  </p>

  <div class="join">
    <button
      onclick={goPrevious}
      class="btn btn-xs btn-ghost join-item"
      disabled={!result?.pageInfo?.hasPreviousPage}
    >
      <ChevronLeft size="14" />
    </button>

    <button
      onclick={goNext}
      class="btn btn-xs btn-ghost join-item"
      disabled={!result?.pageInfo?.hasNextPage}
    >
      <ChevronRight size="14" />
    </button>
  </div>
</div>
