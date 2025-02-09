<script>
  import {
    Globe,
    KeySquare,
    User,
    Handshake,
    MonitorSmartphone,
    Theater,
    Tickets,
    DoorOpen,
    Ticket,
  } from "lucide-svelte";
  import Page from "./Page.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import ActorList from "./list/Actor.svelte";
  import ClientList from "./list/Client.svelte";
  import DeviceList from "./list/Device.svelte";
  import TokenList from "./list/Token.svelte";
  import ProviderList from "./list/Provider.svelte";
  import Tabs from "./Tabs.svelte";
  import { getContext } from "svelte";
  import Query from "@/components/Query.svelte";

  let props = $props();
  let query = gql`
    query {
      server {
        stats
      }
    }
  `;

  let { root } = getContext("page");

  let tab = $state(props?.params?.tab || "actors");
  let table = {
    actors: {
      plural: "Actors",
      singular: "Actor",
      href: `${root}/actors`,
      active: "btn-error",
      component: ActorList,
      icon: User,
    },
    clients: {
      plural: "Clients",
      singular: "Client",
      href: `${root}/clients`,
      active: "btn-secondary",
      component: ClientList,
      icon: DoorOpen,
    },
    devices: {
      plural: "Devices",
      singular: "Device",
      href: `${root}/devices`,
      active: "btn-info",
      component: DeviceList,
      icon: MonitorSmartphone,
    },
    sso: {
      plural: "Providers",
      singular: "SSO",
      href: `${root}/sso`,
      active: "btn-primary",
      component: ProviderList,
      statsKey: "providers",
      icon: Handshake,
    },
    tokens: {
      plural: "Tokens",
      singular: "Token",
      href: `${root}/tokens`,
      active: "btn-accent",
      component: TokenList,
      icon: Ticket,
    },
  };
</script>

<Page {...props}>
  <Tabs style="cards" {tab} {props} tabs={table} goto />
</Page>
