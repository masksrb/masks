import { gql } from "@urql/svelte";
import { Github, ShieldQuestion } from "lucide-svelte";

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

export const ProviderFragment = gql`
  fragment ProviderFragment on Provider {
    id
    name
    type
    setup
    disabled
    common
    settings
    callbackUri
    createdAt
    updatedAt
    disabledAt
  }
`;

export const ActorFragment = gql`
  fragment ActorFragment on Actor {
    id
    name
    nickname
    password
    passwordChangedAt
    passwordChangeable
    identifier
    identifierType
    identiconId
    loginEmail
    loginEmails {
      address
      verifiedAt
    }
    avatar
    avatarCreatedAt
    passwordChangedAt
    passwordChangeable
    secondFactor
    savedBackupCodesAt
    remainingBackupCodes
    secondFactors {
      ... on HardwareKey {
        id
      }
      ... on Phone {
        number
      }
      ... on OtpSecret {
        id
      }
    }
    hardwareKeys {
      id
      name
      createdAt
      icons {
        light
        dark
      }
    }
    phones {
      number
      createdAt
      verifiedAt
    }
    otpSecrets {
      id
      name
      createdAt
    }
    singleSignOns {
      identifier
      createdAt

      provider {
        type
        name
      }
    }
    stats
    createdAt
    updatedAt
  }
`;

export const ClientFragment = gql`
  fragment ClientFragment on Client {
    id
    secret
    scopes
    redirectUris
    subjectType
    name
    type
    logo
    bgLight
    bgDark
    sectorIdentifier
    pairwiseSalt
    allowPasswords
    allowLoginLinks
    autofillRedirectUri
    fuzzyRedirectUri
    idTokenExpiresIn
    accessTokenExpiresIn
    authorizationCodeExpiresIn
    refreshTokenExpiresIn
    clientTokenExpiresIn
    loginLinkExpiresIn
    authAttemptExpiresIn
    emailVerificationExpiresIn
    loginLinkFactorExpiresIn
    ssoFactorExpiresIn
    passwordFactorExpiresIn
    secondFactorBackupCodeExpiresIn
    secondFactorPhoneExpiresIn
    secondFactorOtpExpiresIn
    secondFactorWebauthnExpiresIn
    internalTokenExpiresIn
    lifetimeTypes
    stats
    createdAt
    updatedAt
  }
`;

export const TokenFragment = gql`
  fragment TokenFragment on Token {
    id
    name
    type
    secret
    usable
    expired
    redirectUri
    scopes
    nonce
    createdAt
    expiresAt
    revokedAt
    client {
      id
      name
    }
    actor {
      id
      name
      identifier
      identiconId
    }
    device {
      id
      name
      type
      ip
      os
    }
  }
`;

export const DeviceFragment = gql`
  fragment DeviceFragment on Device {
    id
    name
    type
    ip
    os
    userAgent
    version
    createdAt
    updatedAt
    blockedAt
  }
`;

export const PageInfoFragment = gql`
  fragment PageInfoFragment on PageInfo {
    hasNextPage
    hasPreviousPage
    startCursor
    endCursor
  }
`;

function redirectTimeout(cb, timeout = 300) {
  const thresholdMillis = 5000;
  const lastReloadTimestamp = parseInt(
    localStorage.getItem("lastReloadTimestamp") || "0",
    10
  );
  const currentTimestamp = Date.now();

  if (currentTimestamp - lastReloadTimestamp < thresholdMillis) {
    return cb(true);
  }

  localStorage.setItem("lastReloadTimestamp", currentTimestamp.toString());

  setTimeout(cb, timeout);
}

export { redirectTimeout };
