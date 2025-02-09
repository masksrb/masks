import { gql } from "@urql/svelte";

export const ProviderFragment = gql`
  fragment ProviderFragment on Provider {
    id
    name
    type
    setup
    disabled
    common
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
    validSecondFactors
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
    name
    type
    logo
    secret
    scopes
    styles
    stylesUrl
    redirectUris
    subjectType
    internal
    sectorIdentifier
    pairwiseSalt
    allowNicknames
    allowPasswords
    allowLoginLinks
    allowProfiles
    allowSso
    allowFactor2
    allowOtp
    allowPhones
    allowWebauthn
    allowDiscovery
    allowBackupCodes
    allowEmails
    autofillRedirectUri
    fuzzyRedirectUri
    idTokenDuration
    accessTokenDuration
    authorizationCodeDuration
    refreshTokenDuration
    clientTokenDuration
    loginLinkDuration
    loginAttemptDuration
    verifiedEmailDuration
    emailLoginDuration
    ssoLoginDuration
    passwordLoginDuration
    backupCode2faDuration
    phone2faDuration
    otp2faDuration
    webauthn2faDuration
    internalTokenDuration
    onboardedProfileDuration
    lifetimeTypes
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
