import { t } from "./copy.js";

export const blocked = (actor) =>
  actor.devices.some((device) => device.blockedAt);

export const actorMarks = (actor) =>
  [
    actor.scopes.some((scope) => scope.startsWith("masks:")) && [
      "manager",
      t("actors.marks.manager"),
      "primary",
    ],
    actor.otpEnabled && [
      "key",
      t("actors.marks.second_factor", { count: actor.backupCodesRemaining }),
      "good",
    ],
    !actor.activated && ["invited", t("actors.marks.invited"), "info"],
    actor.email &&
      !actor.emailVerified && [
        "unconfirmed",
        t("actors.marks.unconfirmed"),
        "warn",
      ],
    actor.pendingApproval && ["waiting", t("actors.marks.waiting"), "warn"],
    actor.recoveryRequestedAt && ["help", t("actors.marks.help"), "warn"],
    actor.suspendedAt && ["suspended", t("actors.marks.suspended"), "bad"],
    blocked(actor) && ["blocked", t("actors.marks.blocked"), "bad"],
  ].filter(Boolean);
