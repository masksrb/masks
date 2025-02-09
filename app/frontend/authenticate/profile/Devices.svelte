<script>
  let { prompt, ...props } = $props();

  import Query from "@/components/Query.svelte";
  import { gql } from "@urql/svelte";
  import { DeviceFragment } from "@/util.js";
  import Device from "./Device.svelte";

  let query = gql`
    query ($id: ID!) {
      auth(id: $id) {
        device {
          ...DeviceFragment
        }
      }
    }

    ${DeviceFragment}
  `;
</script>

<Query {query} variables={{ id: prompt.auth.id }} key="auth" autoquery>
  {#snippet children({ result })}
    <p class="label-uc my-1.5">Your devices</p>

    {#if result?.device}
      <Device device={result.device} />
    {/if}
  {/snippet}
</Query>
