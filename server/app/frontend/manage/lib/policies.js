import { t } from "./copy.js";

export const POLICY_FIELDS = `
  key name signup nickname email emailVerified phone phoneVerified
  passwordMinimum refuseCommonPasswords firstFactors secondFactors secondFactorRequired appsRequireSecondFactor sessionLifetime sessionIdleTimeout refuseBreachedPasswords riskStepUpAt riskRefuseAt
  emailDomains providers confirmation hidden signupScopes archivedAt
`;

const FACTORS = [
  "password",
  "passkey",
  "provider",
  "email_code",
  "otp",
  "backup_codes",
];

const CONFIRMATIONS = ["none", "code", "link", "approval"];

const PRESENCE = ["off", "optional", "required"];

const known = (list, group, value) =>
  list.includes(value) ? t(`policy_rules.${group}.${value}`) : value;

const listed = (values, empty) =>
  values?.length
    ? values.map((value) => known(FACTORS, "factors", value)).join(", ")
    : t(`policy_rules.values.${empty}`);

const yes = (value) =>
  t(value ? "policy_rules.answers.yes" : "policy_rules.answers.no");

const value = (name) => t(`policy_rules.values.${name}`);

const UNITS = [
  [86400, "day"],
  [3600, "hour"],
  [60, "minute"],
];

export function duration(seconds) {
  const [size, unit] = UNITS.find(([held]) => seconds % held === 0) ?? [
    1,
    "second",
  ];

  return t(`policy_rules.units.${unit}`, { count: seconds / size });
}

const term = (name) => t(`policy_rules.terms.${name}`);

function describePolicy(policy) {
  return [
    [term("signup"), policy.signup ? value("open") : value("invitation_only")],
    [term("email_domains"), listed(policy.emailDomains, "any")],
    [term("hidden"), yes(policy.hidden)],
    [term("nickname"), known(PRESENCE, "presence", policy.nickname)],
    [term("email"), known(PRESENCE, "presence", policy.email)],
    [term("email_verified"), yes(policy.emailVerified)],
    [term("phone"), known(PRESENCE, "presence", policy.phone)],
    [term("phone_verified"), yes(policy.phoneVerified)],
    [term("first_factors"), listed(policy.firstFactors, "nothing")],
    [
      term("providers"),
      policy.providers === null
        ? value("every_one")
        : listed(policy.providers, "none"),
    ],
    [
      term("password"),
      t(
        policy.refuseCommonPasswords
          ? "policy_rules.values.not_common"
          : "policy_rules.values.password",
        {
          minimum: policy.passwordMinimum,
        },
      ),
    ],
    [term("second_factors"), listed(policy.secondFactors, "none")],
    [term("second_factor_required"), yes(policy.secondFactorRequired)],
    [term("apps_require_second_factor"), yes(policy.appsRequireSecondFactor)],
    [
      term("session_lifetime"),
      policy.sessionLifetime
        ? duration(policy.sessionLifetime)
        : value("default_lifetime"),
    ],
    [term("refuse_breached"), yes(policy.refuseBreachedPasswords)],
    [
      term("risk_step_up"),
      policy.riskStepUpAt
        ? t("policy_rules.values.at", { score: policy.riskStepUpAt })
        : value("never"),
    ],
    [
      term("risk_refuse"),
      policy.riskRefuseAt
        ? t("policy_rules.values.at", { score: policy.riskRefuseAt })
        : value("never"),
    ],
    [
      term("idle_timeout"),
      policy.sessionIdleTimeout
        ? duration(policy.sessionIdleTimeout)
        : value("never"),
    ],
    [
      term("confirmation"),
      known(CONFIRMATIONS, "confirmations", policy.confirmation),
    ],
    [term("signup_scopes"), listed(policy.signupScopes, "none")],
  ];
}

export function policyDifferences(chosen, fallback) {
  const theirs = new Map(describePolicy(fallback));

  return describePolicy(chosen)
    .filter(([term, value]) => theirs.get(term) !== value)
    .map(([term, value]) => ({ term, value, instead: theirs.get(term) }));
}
