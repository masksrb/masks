import { t } from "./copy.js";

export const protocolName = (protocol) => t(`providers.protocols.${protocol}`);

export const secretMissing = (provider) =>
  !["saml", "mcp"].includes(provider.protocol) &&
  !(provider.tokenAuthMethod === "signed_secret"
    ? provider.privateKeyHeld
    : provider.secretHeld);

export const providerMarks = (provider) =>
  [
    provider.role === "delegate" &&
      provider.protocol !== "mcp" && [
        "owns",
        t("providers.marks.owns"),
        "primary",
      ],
    provider.trustsEmail && ["mail", t("providers.marks.trusts_email"), "good"],
    provider.receivesSignals && [
      "signals",
      t("providers.marks.signals"),
      "info",
    ],
    provider.delegates && ["delegates", t("providers.marks.delegates"), "info"],
    secretMissing(provider) && [
      "unconfirmed",
      t("providers.marks.no_secret"),
      "warn",
    ],
  ].filter(Boolean);
