import { plural } from "./format.js";

export const POLICY_FIELDS = `
  key name signup nickname email emailVerified phone phoneVerified
  passwordMinimum refuseCommonPasswords firstFactors secondFactors secondFactorRequired appsRequireSecondFactor sessionLifetime sessionIdleTimeout refuseBreachedPasswords riskStepUpAt riskRefuseAt
  emailDomains providers confirmation hidden signupScopes archivedAt
`;

const FACTORS = {
  password: "password",
  passkey: "passkey",
  provider: "provider",
  email_code: "emailed code",
  otp: "authenticator app",
  backup_codes: "backup codes",
};

const CONFIRMATIONS = {
  none: "none",
  code: "emailed code",
  link: "emailed link",
  approval: "manager approval",
};

const listed = (values, empty) =>
  values?.length
    ? values.map((value) => FACTORS[value] ?? value).join(", ")
    : empty;

const yes = (value) => (value ? "yes" : "no");

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
  const count = seconds / size;

  return plural(count, unit);
}

function describePolicy(policy) {
  return [
    ["Sign up", policy.signup ? "open" : "invitation only"],
    ["Email domains", listed(policy.emailDomains, "any")],
    ["Hides who has an account", yes(policy.hidden)],
    ["Nickname", policy.nickname],
    ["Email", policy.email],
    ["Confirmed email", yes(policy.emailVerified)],
    ["Phone", policy.phone],
    ["Confirmed phone", yes(policy.phoneVerified)],
    ["Signs in with", listed(policy.firstFactors, "nothing")],
    [
      "Providers",
      policy.providers === null
        ? "every one"
        : listed(policy.providers, "none"),
    ],
    [
      "Password",
      `at least ${policy.passwordMinimum} characters${policy.refuseCommonPasswords ? ", not a common one" : ""}`,
    ],
    ["Second factors", listed(policy.secondFactors, "none")],
    ["Second factor required", yes(policy.secondFactorRequired)],
    ["Second factor at every app sign-in", yes(policy.appsRequireSecondFactor)],
    [
      "Session lifetime",
      policy.sessionLifetime ? duration(policy.sessionLifetime) : "14 days",
    ],
    ["Refuses breached passwords", yes(policy.refuseBreachedPasswords)],
    [
      "Second factor from risk",
      policy.riskStepUpAt ? `at ${policy.riskStepUpAt}` : "never",
    ],
    [
      "Refused from risk",
      policy.riskRefuseAt ? `at ${policy.riskRefuseAt}` : "never",
    ],
    [
      "Idle timeout",
      policy.sessionIdleTimeout ? duration(policy.sessionIdleTimeout) : "never",
    ],
    ["Confirmation", CONFIRMATIONS[policy.confirmation] ?? policy.confirmation],
    ["Signup scopes", listed(policy.signupScopes, "none")],
  ];
}

export function policyDifferences(chosen, fallback) {
  const theirs = new Map(describePolicy(fallback));

  return describePolicy(chosen)
    .filter(([term, value]) => theirs.get(term) !== value)
    .map(([term, value]) => ({ term, value, instead: theirs.get(term) }));
}
