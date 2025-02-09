<script>
  import _ from "lodash-es";
  import Page from "./Page.svelte";

  import {
    LogIn,
    Handshake,
    Cog,
    Mail,
    Smartphone,
    SquareActivity,
    ImageUp,
  } from "lucide-svelte";
  import Time from "@/components/Time.svelte";
  import PasswordInput from "@/components/PasswordInput.svelte";
  import SettingClientsTab from "@/manage/SettingClientsTab.svelte";
  import SettingActorsTab from "@/manage/SettingActorsTab.svelte";
  import SettingGeneralTab from "@/manage/SettingGeneralTab.svelte";
  import SettingStorageTab from "@/manage/SettingStorageTab.svelte";
  import SettingMonitoringTab from "@/manage/SettingMonitoringTab.svelte";
  import SettingEmailTab from "@/manage/SettingEmailTab.svelte";
  import SettingPhoneTab from "@/manage/SettingPhoneTab.svelte";
  import Tabs from "./Tabs.svelte";
  import { mutationStore, gql, getContextClient } from "@urql/svelte";

  let props = $props();
  let result = $state();
  let loading = $state(true);
  let errors = $state();
  let install = $state({});
  let client = getContextClient();
  let changes = $state({});
  let original = $state({});
  let changed = $state(false);

  function customizer(objValue, srcValue) {
    if (_.isArray(objValue)) {
      return srcValue;
    }
  }

  let change = (opts, { reset } = {}) => {
    if (reset) {
      changes = _.mergeWith({}, opts, customizer);
    } else {
      changes = _.mergeWith(changes, opts, customizer);
    }

    install = _.mergeWith(install, changes, customizer);
    changed = !_.isEqual(original, install);
  };

  let save = () => {
    updateSettings(changes);
  };

  let reset = () => {
    changed = false;
    install = _.mergeWith({}, original);
    changes = {};
  };

  let updateSettings = (input = {}) => {
    result = mutationStore({
      client,
      query: gql`
        mutation ($input: InstallationInput!) {
          install(input: $input) {
            install {
              name
              url
              timezone
              region
              theme
              needsRestart
              faviconUrl
              lightLogoUrl
              darkLogoUrl
              clients
              integration
              actors
              devices
              sessions
              emails
              nicknames
              passwords
              backupCodes
              needsRestart
              createdAt
              updatedAt
            }
            errors
          }
        }
      `,
      variables: { input },
    });

    result.subscribe((result) => {
      if (!result) {
        return;
      }

      loading = true;
      errors = null;

      if (!result?.data?.install) {
        return;
      }

      let data = result.data.install;

      errors = data.errors;
      original = data.install;
      install = _.cloneDeep(data.install);
      changes = {};
      change({});
      loading = false;
    });
  };

  let tabs = {
    general: {
      name: "General",
      href: "/manage/settings#general",
      icon: Cog,
      component: SettingGeneralTab,
    },
    login: {
      name: "Login",
      href: "/manage/settings#login",
      component: SettingActorsTab,
      icon: LogIn,
    },
    clients: {
      name: "Clients",
      href: "/manage/settings#clients",
      component: SettingClientsTab,
      icon: Handshake,
    },
    emails: {
      name: "Email",
      href: "/manage/settings#emails",
      component: SettingEmailTab,
      icon: Mail,
    },
    phones: {
      name: "Phone",
      href: "/manage/settings#phones",
      component: SettingPhoneTab,
      icon: Smartphone,
    },
    storage: {
      name: "Storage",
      href: "/manage/settings#storage",
      component: SettingStorageTab,
      icon: ImageUp,
    },
    monitoring: {
      name: "Monitoring",
      href: "/manage/settings#monitoring",
      component: SettingMonitoringTab,
      icon: SquareActivity,
    },
  };

  let tab = $state(window?.location?.hash.slice(1) || Object.keys(tabs)[0]);
  let tabData = $state({});

  updateSettings();
</script>

<Page {...props} loading={!install?.createdAt}>
  <div class="flex items-center gap-1.5 px-1.5 mb-3">
    <div class="grow p-1.5 pt-0">
      <div class="flex items-center gap-1.5 grow">
        <div class="font-bold">{tabData.name}</div>
        <div class="opacity-75">settings</div>
      </div>
      <div class="flex items-center gap-1.5">
        {#if install.updatedAt}
          {#key install.updatedAt}
            <p class="text-xs opacity-75">
              last saved
              <Time timestamp={install?.updatedAt} />
            </p>
          {/key}
        {/if}
      </div>
    </div>

    {#if install.needsRestart}
      <p class="badge badge-warning badge-sm rounded">restart required</p>
    {/if}

    {#if changed}
      <button class="btn btn-link btn-sm !text-error" onclick={reset}>
        reset
      </button>
    {/if}

    <button class="btn btn-success btn-sm" onclick={save} disabled={!changed}>
      save
    </button>
  </div>

  <Tabs {tab} {tabs} onchange={(t) => (tabData = t)} goto name>
    {#snippet component(Tab)}
      <Tab {change} settings={install} {errors} {loading} {...props} />
    {/snippet}
  </Tabs>
</Page>
