<script>
import CodeForm from "../shared/CodeForm.svelte";
import Head from "../shared/Head.svelte";
import Identified from "../shared/Identified.svelte";
import Resend from "../shared/Resend.svelte";

let { login } = $props();
</script>

<Head {login} title={login.t("title")} lede={login.t("lede", { identifier: login.identifier ?? "" })} />

<Identified {login} />

<CodeForm {login} event="email-code:verify" />

<Resend {login} event="email-code:send" ready={login.auth.emailCode?.resendable !== false} />
