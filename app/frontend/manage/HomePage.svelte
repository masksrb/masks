<script>
  import {
    KeySquare,
    LogIn,
    User,
    Handshake,
    MonitorSmartphone,
    Mail,
    Phone,
  } from "lucide-svelte";
  import { route } from "@mateothegreat/svelte5-router";
  import Page from "./Page.svelte";
  import Time from "@/components/Time.svelte";
  import { queryStore, gql, getContextClient } from "@urql/svelte";
  import ActorList from "./list/Actor.svelte";
  import ClientList from "./list/Client.svelte";
  import DeviceList from "./list/Device.svelte";
  import TokenList from "./list/Token.svelte";
  import Tabs from "./Tabs.svelte";

  let props = $props();
  let query = $derived(
    queryStore({
      client: getContextClient(),
      query: gql`
        query {
          install {
            stats
          }
        }
      `,
      requestPolicy: "network-only",
    })
  );

  let stats = $state({});
  let data = $state({});
  let subscribe = () => {
    query.subscribe((r) => {
      data = r?.data?.install || {};
      stats = r?.data?.install?.stats || {};
    });
  };

  subscribe();

  let changeTab = (key) => {
    return (e) => {
      e.preventDefault();
      e.stopPropagation();

      tab = key;
    };
  };

  let tab = $state(props?.params?.tab || "tokens");
  let table = {
    tokens: {
      plural: "Tokens",
      singular: "Token",
      href: "/manage/tokens",
      component: TokenList,
      icon: KeySquare,
    },
    actors: {
      plural: "Actors",
      singular: "Actor",
      href: "/manage/actors",
      component: ActorList,
      icon: User,
    },
    clients: {
      plural: "Clients",
      singular: "Client",
      href: "/manage/clients",
      component: ClientList,
      icon: Handshake,
    },
    devices: {
      plural: "Devices",
      singular: "Device",
      href: "/manage/devices",
      component: DeviceList,
      icon: MonitorSmartphone,
    },
  };
</script>

<Page {...props}>
  <Tabs {tab} tabs={table} {stats} goto />
</Page>
