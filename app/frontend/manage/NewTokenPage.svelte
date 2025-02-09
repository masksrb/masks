<script>
  import Page from "./Page.svelte";
  import { run, preventDefault } from "svelte/legacy";
  import { goto } from "@mateothegreat/svelte5-router";
  import { KeySquare, AlertTriangle, X, UserPlus, Save } from "lucide-svelte";
  import Alert from "@/components/Alert.svelte";
  import ScopesEditor from "./ScopesEditor.svelte";

  let props = $props();
  let input = $state({});

  let change = (changes) => {
    input = { ...input, ...changes };
  };
</script>

<Page {...props}>
  <div class="flex flex-col gap-3">
    <Alert type="warn" icon={AlertTriangle}>
      <div class="flex flex-col gap-3">
        <div>
          <b>Keep your tokens <i>secret</i></b>. Tokens have the ability to
          perform sensitive and even dangerous actions...
        </div>
      </div></Alert
    >

    <label class="input input-bordered flex items-center gap-3">
      <span class="label-text-alt opacity-75">client</span>

      <input
        type="text"
        class="grow"
        placeholder="enter the client identifier..."
      />
    </label>

    <label class="input input-bordered flex items-center gap-3">
      <span class="label-text-alt opacity-75">actor</span>

      <input
        type="text"
        class="grow"
        placeholder="enter the actor's nickname or email..."
      />
    </label>

    <ScopesEditor required {change} scopes={input.scopes} />
  </div>
</Page>
