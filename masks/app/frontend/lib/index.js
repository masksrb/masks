import _ from "lodash-es";

export * from "./gql";
export * from "./login";
export * from "./consumer";

export const iconifyProvider = (provider) => {
  const type = provider?.type;
  const types = {
    apple: "logos:apple",
    github: "logos:github-octocat",
    google: "logos:google-icon",
    facebook: "logos:facebook",
    twitter: "logos:twitter",
    generic: "material-symbols-light:handshake-outline-rounded",
  };

  return types[type] || types.generic;
};

function redirectTimeout(cb, timeout = 300) {
  const thresholdMillis = 5000;
  const lastReloadTimestamp = Number.parseInt(
    localStorage.getItem("lastReloadTimestamp") || "0",
    10,
  );
  const currentTimestamp = Date.now();

  if (currentTimestamp - lastReloadTimestamp < thresholdMillis) {
    return cb(true);
  }

  localStorage.setItem("lastReloadTimestamp", currentTimestamp.toString());

  setTimeout(cb, timeout);
}

export { redirectTimeout };
