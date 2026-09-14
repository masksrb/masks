module SamlIdentity
  PROTOCOL = "saml".freeze
  PROTOCOL_NS = "urn:oasis:names:tc:SAML:2.0:protocol".freeze
  ASSERTION_NS = "urn:oasis:names:tc:SAML:2.0:assertion".freeze
  METADATA_NS = "urn:oasis:names:tc:SAML:2.0:metadata".freeze
  DSIG_NS = "http://www.w3.org/2000/09/xmldsig#".freeze
  POST_BINDING = "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST".freeze
  REDIRECT_BINDING = "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect".freeze

  PERSISTENT = "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent".freeze
  EMAIL = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress".freeze
  UNSPECIFIED = "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified".freeze
  NAME_ID_FORMATS = [ PERSISTENT, EMAIL, UNSPECIFIED ].freeze

  SUCCESS = "urn:oasis:names:tc:SAML:2.0:status:Success".freeze
  RESPONDER = "urn:oasis:names:tc:SAML:2.0:status:Responder".freeze
  REQUESTER = "urn:oasis:names:tc:SAML:2.0:status:Requester".freeze
  REQUEST_DENIED = "urn:oasis:names:tc:SAML:2.0:status:RequestDenied".freeze
  NO_PASSIVE = "urn:oasis:names:tc:SAML:2.0:status:NoPassive".freeze
  INVALID_NAME_ID_POLICY = "urn:oasis:names:tc:SAML:2.0:status:InvalidNameIDPolicy".freeze

  PASSWORD_CONTEXT = "urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport".freeze
  MFA_CONTEXT = "https://refeds.org/profile/mfa".freeze

  SCOPES = [ Scopes::OPENID, Scopes::PROFILE, Scopes::EMAIL ].freeze
  DEFAULT_ATTRIBUTES = {
    "email" => "email",
    "name" => "name",
    "given_name" => "given_name",
    "family_name" => "family_name",
    "preferred_username" => "preferred_username"
  }.freeze

  LIFETIME = 5.minutes
  CLOCK_SKEW = 3.minutes
  LIMIT = 64.kilobytes

  class Refused < StandardError; end

  def self.sso_url(issuer)
    "#{issuer.url}/saml/sso"
  end

  def self.metadata_url(issuer)
    "#{issuer.url}/saml/metadata"
  end

  def self.entity_id(issuer)
    metadata_url(issuer)
  end
end
