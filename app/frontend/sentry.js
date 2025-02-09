import * as Sentry from "@sentry/svelte";

export function sentry(config) {
  if (!config?.dsn) {
    return;
  }

  Sentry.init({
    dsn: config.dsn,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration(),
    ],
    tracesSampleRate: 1.0,
    replaysSessionSampleRate: 0.1,
    replaysOnErrorSampleRate: 1.0,
  });
}
