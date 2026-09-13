class PushedRequest < Token
  include CarriesAuthorization

  PREFIX = "urn:ietf:params:oauth:request_uri:".freeze

  def self.lifetime
    90.seconds
  end

  def self.push!(authorization)
    mint!(**attributes_for(authorization))
  end

  def self.urn?(value)
    value.to_s.start_with?(PREFIX)
  end

  def self.claim_urn(value, client:)
    return nil unless urn?(value)

    secret = value.to_s.delete_prefix(PREFIX)

    return nil unless redeem(secret)&.pushed_by?(client)

    claim(secret)
  end

  def request_uri
    "#{PREFIX}#{secret}"
  end

  def pushed_by?(client)
    client.present? && client_id == client.id
  end
end
