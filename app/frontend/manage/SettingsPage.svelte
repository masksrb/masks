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
    Blocks,
    Activity,
  } from "lucide-svelte";
  import Mutation from "@/components/Mutation.svelte";
  import Time from "@/components/Time.svelte";
  import { ClientFragment } from "@/lib";
  import SettingClientsTab from "@/manage/SettingClientsTab.svelte";
  import SettingActorsTab from "@/manage/SettingActorsTab.svelte";
  import SettingGeneralTab from "@/manage/SettingGeneralTab.svelte";
  import SettingStorageTab from "@/manage/SettingStorageTab.svelte";
  import SettingMonitoringTab from "@/manage/SettingMonitoringTab.svelte";
  import SettingEmailTab from "@/manage/SettingEmailTab.svelte";
  import SettingPhoneTab from "@/manage/SettingPhoneTab.svelte";
  import Tabs from "./Tabs.svelte";
  import { gql } from "@urql/svelte";

  let props = $props();
  let loading = $state(true);
  let errors = $state();
  let server = $state({});
  let changes = $state({});
  let original = $state({});
  let changed = $state(false);

  function customizer(objValue, srcValue) {
    if (_.isArray(objValue)) {
      return srcValue;
    }

    if (_.isEmpty(objValue)) {
      return srcValue;
    }

    if (typeof objValue === "undefined") {
      return srcValue;
    }
  }

  let change = (opts) => {
    changes = _.mergeWith(changes, opts, customizer);
    server = _.mergeWith(server, changes, customizer);
    changed = !_.isEqual(original, server);
  };

  let save = (mutate) => {
    return () => {
      mutate(changes);
    };
  };

  let reset = () => {
    changed = false;
    server = _.mergeWith({}, original);
    changes = {};
  };

  let input = {};
  let query = gql`
    mutation ($input: ConfInput!) {
      conf(input: $input) {
        server {
          url
          name
          themeName
          themeHomepage
          lightLogoUrl
          darkLogoUrl
          faviconUrl
          emailFrom
          emailReplyTo
          storageAdapter
          emailAdapter
          phoneAdapter
          phoneCountry
          sentryDsn
          newrelicApp
          newrelicLicenseKey
          adapters {
            key
            name
            type
            setup
            primary
            emailAdapter
            phoneAdapter
            storageAdapter
            config
          }
          adapterTypes {
            name
            type
            emailAdapter
            phoneAdapter
            storageAdapter
          }
          defaultClient {
            scopes
            redirectUris
            subjectType
            internal
            sectorIdentifier
            pairwiseSalt
            allowNicknames
            allowPasswords
            allowLoginLinks
            allowProfiles
            allowSso
            allowFactor2
            allowOtp
            allowPhones
            allowWebauthn
            allowDiscovery
            allowBackupCodes
            allowEmails
            autofillRedirectUri
            fuzzyRedirectUri
            idTokenDuration
            accessTokenDuration
            authorizationCodeDuration
            refreshTokenDuration
            clientTokenDuration
            loginLinkDuration
            loginAttemptDuration
            verifiedEmailDuration
            emailLoginDuration
            ssoLoginDuration
            passwordLoginDuration
            backupCode2faDuration
            phone2faDuration
            otp2faDuration
            webauthn2faDuration
            internalTokenDuration
            onboardedProfileDuration
            lifetimeTypes
          }
          nicknameFormat
          nicknameMinChars
          nicknameMaxChars
          passwordMinChars
          passwordMaxChars
          backupCodeMinChars
          backupCodeMaxChars
          backupCodeLimit
          sessionInactive
          sessionCookieLifetime
          deviceCookieLifetime
          subjectTypes
          tz
          createdAt
          updatedAt
        }
        errors
      }
    }
  `;

  let key = $state(Math.random());

  let updateSettings = (result) => {
    if (!result) {
      return;
    }

    errors = null;

    if (!result?.server) {
      return;
    }

    key = Math.random();
    errors = result.errors;
    original = result.server;
    server = _.cloneDeep(result.server);
    adapters = _.sortBy(server.adapters, ["primary", "setup"]).reverse();
    change({});
    loading = false;
  };

  let root = $derived(`${props.root}/settings`);
  let tabs = {
    general: {
      name: "General",
      href: `${root}`,
      icon: Cog,
      component: SettingGeneralTab,
    },
    login: {
      name: "Auth",
      href: `${root}#login`,
      component: SettingActorsTab,
      icon: LogIn,
    },
    clients: {
      name: "Clients",
      href: `${root}#clients`,
      component: SettingClientsTab,
      icon: Handshake,
    },
    emails: {
      name: "Emails",
      href: `${root}#emails`,
      component: SettingEmailTab,
      icon: Mail,
    },
    phones: {
      name: "Phones",
      href: `${root}#phones`,
      component: SettingPhoneTab,
      icon: Smartphone,
    },
    storage: {
      name: "Storage",
      href: `${root}#storage`,
      component: SettingStorageTab,
      icon: ImageUp,
    },
    monitoring: {
      name: "Monitoring",
      href: `${root}#monitoring`,
      component: SettingMonitoringTab,
      icon: Activity,
    },
  };

  let tab = $state(window?.location?.hash.slice(1) || Object.keys(tabs)[0]);
  let tabData = $state({});
  let adapters = $state({});
</script>

<Mutation {query} input={{}} key="conf" onmutate={updateSettings} autorun>
  {#snippet children({ mutate, mutating })}
    <Page {...props}>
      <div class="flex items-center gap-1.5 px-1.5 mb-3">
        <div class="grow p-1.5 pt-0">
          <div class="flex items-center gap-1.5 grow">
            <div class="font-bold">Settings</div>
          </div>
          <div class="flex items-center gap-1.5">
            {#if server.updatedAt}
              {#key server.updatedAt}
                <p class="label-xs">
                  last saved
                  <Time timestamp={server?.updatedAt} />
                </p>
              {/key}
            {:else}
              <p class="text-xs opacity-50 italic">loading...</p>
            {/if}
          </div>
        </div>

        {#if server.needsRestart}
          <p class="badge badge-warning badge-sm rounded">restart required</p>
        {/if}

        {#if changed}
          <button class="btn btn-link btn-sm !text-error" onclick={reset}>
            reset
          </button>
        {/if}

        <button
          class="btn btn-success btn-sm"
          onclick={save(mutate)}
          disabled={!changed}
        >
          save
        </button>
      </div>

      <Tabs {tab} {tabs} onchange={(t) => (tabData = t)} goto name>
        {#snippet component(Tab)}
          {#if !loading}
            {#key key}
              <Tab
                {change}
                settings={server}
                {adapters}
                {errors}
                {loading}
                {...props}
              />
            {/key}
          {/if}
        {/snippet}
      </Tabs>
    </Page>
  {/snippet}
</Mutation>
