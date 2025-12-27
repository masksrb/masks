import "./app.css";

// import App from "@/App.svelte";
// import Component from "@/client/Page.svelte";
// import { mount } from "svelte";
import { sentry } from "../sentry.js";

const props = { ...window.MASKS };

sentry(props.sentry);

window.masks = {
  fetch: (url, options) => {
    const csrf = document.querySelector('meta[name="csrf-token"]').content;

    options.headers = { ...options.headers || {} }

    if (csrf) {
      options.headers["X-CSRF-Token"] = csrf;
    }

    if (options.json) {
      options.headers['Accept'] = 'application/json';
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(options.json);

      delete options.json;
    }

    return fetch(url, options);
  },

  recaptcha: (opts) => {
    const isEnterprise = opts.variant === 'enterprise';
    const isCheckbox = opts.variant === 'v2_checkbox';
    const api = isEnterprise ? grecaptcha.enterprise : grecaptcha;

    const submitToken = async (token) => {
      const response = await masks.fetch(opts.path, {
        method: 'POST',
        credentials: "same-origin",
        json: { token },
      });

      if (response.ok) {
        window.location.reload();
      }
    };

    if (isCheckbox) {
      // v2 checkbox - visible widget, callback on user completion
      api.render(opts.id, {
        sitekey: opts.sitekey,
        callback: submitToken,
      });
    } else {
      // enterprise, v3, v2_invisible - invisible, auto-execute
      const widgetId = api.render(opts.id, {
        sitekey: opts.sitekey,
        badge: 'inline',
        size: 'invisible',
      });

      api.ready(async () => {
        const token = await api.execute(widgetId, { action: opts.action || 'login' });
        await submitToken(token);
      });
    }
  },

  turnstile: (opts) => {
    turnstile.render(`#${opts.id}`, {
      sitekey: opts.sitekey,
      callback: async (token) => {
        const response = await masks.fetch(opts.path, {
          method: 'POST',
          credentials: "same-origin",
          json: { token },
        });

        if (response.ok) {
          window.location.reload();
        }
      }
    });
  },

  hcaptcha: (opts) => {
    const isInvisible = opts.variant === 'invisible';

    const submitToken = async (token) => {
      const response = await masks.fetch(opts.path, {
        method: 'POST',
        credentials: "same-origin",
        json: { token },
      });

      if (response.ok) {
        window.location.reload();
      }
    };

    if (isInvisible) {
      const widgetId = hcaptcha.render(opts.id, {
        sitekey: opts.sitekey,
        size: 'invisible',
        callback: submitToken,
      });

      hcaptcha.execute(widgetId);
    } else {
      // checkbox - visible widget
      hcaptcha.render(opts.id, {
        sitekey: opts.sitekey,
        callback: submitToken,
      });
    }
  }
}


