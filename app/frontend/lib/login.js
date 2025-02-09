import _ from "lodash-es";

export const VERIFIED = {
  "password:change": {
    to: "change your password",
    cta: "change",
  },
  "email:create": {
    to: "add ${email}",
    cta: "add",
  },
  "email:delete": {
    to: "remove ${email}",
    cta: "remove",
  },
  "sso:delete": {
    to: "unlink ${provider}",
    cta: "unlink",
  },
  "backup-codes:replace": {
    to: "save your backup codes",
    cta: "save",
    if: (p) => p.enabledSecondFactor,
  },
  "webauthn:create": {
    to: "add a security key",
    cta: "add",
    if: (p) => p.enabledSecondFactor,
  },
  "webauthn:delete": {
    to: "remove ${webauthn}",
    cta: "remove",
    if: (p) => p.enabledSecondFactor,
  },
  "otp:create": {
    to: "add an authenticator app",
    cta: "add",
    if: (p) => p.enabledSecondFactor,
  },
  "otp:delete": {
    to: "remove your authenticator app",
    cta: "remove",
    if: (p) => p.enabledSecondFactor,
  },
  "phone:create": {
    to: "add your phone number",
    cta: "add",
    if: (p) => p.enabledSecondFactor,
  },
  "phone:delete": {
    to: "remove your phone number",
    cta: "remove",
    if: (p) => p.enabledSecondFactor,
  },
};

export class Login {
  constructor(result, opts) {
    this.url = opts?.url || window.location.href;
    this.consumer = opts?.consumer;
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
    return new Login({ ...this.auth }, this.cloneOpts()).noSudo();
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
      return new Login(
        { ...this.auth },
        this.cloneOpts({
          ...vars,
          verifying: vars.event,
          event: vars.event.event,
        })
      );
    }

    const input = {
      event: vars.event,
      updates: vars.updates || {},
    };

    if (vars.sudo && this.verifying) {
      input.event = this.event;
      input.updates = { ...this.updates, ...vars.updates };
    }

    return this.mutate(input).then((result) => {
      if (
        vars.sudo &&
        !result.loadingError &&
        !result.warnings?.includes("invalid-factor")
      ) {
        result.verifying?.done?.(result);
        result.noSudo();
      }

      return result;
    });
  }

  async mutate(input) {
    this.loading = true;

    const headers = {
      Accept: "application/json",
    };

    let data;

    if (input?.upload) {
      data = new FormData();

      if (input?.event) {
        data.append("event", input.event);
      }

      if (input?.updates) {
        for (const [key, value] of Object.entries(input.updates)) {
          data.append(key, value);
        }
      }
    } else {
      headers["Content-Type"] = "application/json";
      data = JSON.stringify({ event: input.event, ...(input?.updates || {}) });
    }

    const response = await this.consumer.fetch(this.url, {
      method: "POST",
      body: data,
      headers,
    });

    const json = await response.json();

    this.loading = false;

    return new Login(json, this.cloneOpts());
  }

  startOver(logout = false) {
    const prompt = new Login(this.auth, this.cloneOpts());

    prompt.auth.actor = null;
    prompt.auth.errorCode = null;
    prompt.auth.errorMessage = null;
    prompt.auth.prompt = "identify";
    prompt.endSudo();

    return this.mutate({ event: logout ? "logout" : "reset" });
  }

  cloneOpts(overrides) {
    return { consumer: this.consumer, ...this.opts, ...(overrides || {}) };
  }

  get enabledSecondFactor() {
    return (
      this.auth?.actor?.validSecondFactors && this.auth?.actor?.secondFactor
    );
  }

  ssoProviders() {
    const list = [];
    const providers = [];

    for (const sso of this.auth?.actor?.singleSignOns || []) {
      list.push(sso);
      providers.push(sso.provider.type);
    }

    for (const provider of this.auth?.providers || []) {
      if (!providers.includes(provider.type)) {
        list.push({ provider });
      }
    }

    return list;
  }
}
