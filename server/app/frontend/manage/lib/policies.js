export const POLICY_FIELDS = `
  key name signup nickname email emailVerified phone phoneVerified
  passwordMinimum refuseCommonPasswords firstFactors secondFactors secondFactorRequired
  emailDomains providers confirmation hidden signupScopes archivedAt
`;

const FACTORS = {
  password: "password",
  passkey: "passkey",
  provider: "provider",
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

export function describePolicy(policy) {
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
