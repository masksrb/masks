import _ from "lodash-es";
import { writable } from "svelte/store";
import { mutationStore, gql, getContextClient } from "@urql/svelte";
import EntryFragment from "./entry.graphql?raw";

export const QUERY = gql`
  mutation ($input: EnterInput!) {
    enter(input: $input) {
      entry {
        ...EntryFragment
      }
    }
  }

  ${EntryFragment}
`;

export const LEAVE = gql`
  mutation ($input: LeaveInput!) {
    leave(input: $input) {
      entry {
        ...EntryFragment
      }
    }
  }

  ${EntryFragment}
`;

export const PROMPTS = [
  "identify",
  "device",
  "credentials",
  "sso",
  "sso-error",
  "sso-accept",
  "sso-link",
  "second-factor",
  "login-code",
  "login-link",
  "verify-email",
  "reset-password",
  "invalid-redirect",
  "missing-scopes",
  "missing-nonce",
  "expired-state",
  "access-denied",
  "authorize",
  "profile",
  "success",
];

export const VERIFIED = {
  "password:change": {
    to: "change your password",
    cta: "change",
    toast: "Password changed",
  },
  "email:create": {
    to: "add ${email}",
    cta: "add",
    toast: "Added ${email}",
  },
  "email:delete": {
    to: "remove ${email}",
    cta: "remove",
    toast: "Removed ${email}",
  },
  "sso:unlink": {
    to: "unlink ${provider}",
    cta: "unlink",
    toast: "Unlinked ${provider}",
  },
  "backup-codes:replace": {
    to: "save your backup codes",
    cta: "save",
    toast: "Backup codes saved",
    if: (p) => p.enabledSecondFactor,
  },
  "webauthn:create": {
    to: "add a security key",
    cta: "add",
    toast: "Security key added",
    if: (p) => p.enabledSecondFactor,
  },
  "webauthn:delete": {
    to: "remove ${webauthn}",
    cta: "remove",
    toast: "Security key removed",
    if: (p) => p.enabledSecondFactor,
  },
  "otp:create": {
    to: "add an authenticator app",
    cta: "add",
    toast: "Authenticator app added",
    if: (p) => p.enabledSecondFactor,
  },
  "otp:delete": {
    to: "remove your authenticator app",
    cta: "remove",
    toast: "Authenticator app deleted",
    if: (p) => p.enabledSecondFactor,
  },
  "phone:create": {
    to: "add your phone number",
    cta: "add",
    toast: "Phone added",
    if: (p) => p.enabledSecondFactor,
  },
  "phone:delete": {
    to: "remove your phone number",
    cta: "remove",
    toast: "Phone removed",
    if: (p) => p.enabledSecondFactor,
  },
};

class Prompt {
  constructor(result, opts) {
    this.graphql = opts?.graphql || getContextClient();
    this.auth = result;
    this.opts = opts || {};
    this.event = opts?.event;
    this.updates = opts?.updates;
    this.extras = this.auth.extras;
    this.warnings = this.auth.warnings;
    this.verifying = opts?.verifying;
    this.loadingError = result.error;
  }

  endSudo() {
    return new Prompt({ ...this.auth }, this.cloneOpts()).noSudo();
  }

  noSudo() {
    this.event = this.opts.event = null;
    this.updates = this.opts.updates = null;
    this.verifying = this.opts.verifying = false;

    return this;
  }

  verification(event, opts) {
    if (!VERIFIED[event]) {
      return;
    }

    return { first: true, second: true, ...VERIFIED[event], ...opts, event };
  }

  refresh(vars) {
    if (vars.event?.event && !this.verifying) {
      return new Prompt(
        { ...this.auth },
        this.cloneOpts({
          ...vars,
          verifying: vars.event,
          event: vars.event.event,
        })
      );
    }

    const input = {
      id: this.auth.id,
      event: vars.event,
      updates: vars.updates || {},
    };

    if (vars.sudo && this.verifying) {
      input.event = this.event;
      input.updates = { ...this.updates, ...vars.updates };
    }

    return this.mutate(QUERY, input).then((result) => {
      if (
        vars.sudo &&
        !result.loadingError &&
        !result.warnings?.includes("invalid-factor")
      ) {
        if (result.verifying?.toast && !result.warnings.length) {
          Masks.toast(result.verifying.toast, result.verifying);
        }

        result.verifying?.done?.(result);
        result.noSudo();
      }

      return result;
    });
  }

  async mutate(query, input, key = "enter") {
    this.loading = true;

    return new Promise((res, _) => {
      const mutation = mutationStore({
        client: this.graphql,
        query,
        variables: { input },
      });

      mutation.subscribe((r) => {
        if (!r || r.fetching) {
          return;
        }

        this.loading = false;

        res(new Prompt(r?.data?.[key]?.entry, this.cloneOpts()));
      });
    });
  }

  startOver(logout = false) {
    const prompt = new Prompt(this.auth, this.cloneOpts());

    prompt.auth.actor = null;
    prompt.auth.errorCode = null;
    prompt.auth.errorMessage = null;
    prompt.auth.prompt = "identify";
    prompt.endSudo();

    return this.mutate(LEAVE, { id: this.auth.id, logout }, "leave");
  }

  cloneOpts(overrides) {
    return { graphql: this.graphql, ...this.opts, ...(overrides || {}) };
  }

  get enabledSecondFactor() {
    return this.validSecondFactor && this.auth?.actor?.secondFactor;
  }

  get validSecondFactor() {
    return (
      this.auth?.actor?.secondFactors?.length &&
      this.auth.actor?.savedBackupCodesAt
    );
  }

  ssoProviders() {
    const list = [];
    const providers = [];

    for (const sso of this.auth?.actor?.singleSignOns || []) {
      list.push(sso);
      providers.push(sso.provider.type);
    }

    for (const provider of this.auth?.client?.providers || []) {
      if (!providers.includes(provider.type)) {
        list.push({ provider });
      }
    }

    return list;
  }
}

export const toasts = writable([]);

export const Masks = {
  prompt: (...args) => new Prompt(...args),
  Prompt,
  toast: (message, vars = null) => {
    const toast = _.template(message)(vars);

    setTimeout(() => {
      toasts.update((v) => v.filter((m) => m !== toast));
    }, 5000);

    toasts.update((v) => [...v, toast]);
  },
};
