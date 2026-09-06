class PendingHandshake < Token
  def self.lifetime
    1.hour
  end

  def self.answered_is_final?
    false
  end

  def self.open!(handshake)
    mint!(
      scopes: Scopes.join(handshake.scopes),
      audience: [ handshake.resource ],
      redirect_uri: handshake.return_to,
      payload: {
        "name" => handshake.name,
        "redirect_uris" => handshake.redirect_uris,
        "state" => handshake.state,
        "auth_method" => handshake.auth_method,
        "backchannel_logout_uri" => handshake.backchannel_logout_uri
      }.compact
    )
  end

  def handshake
    @handshake ||= Handshake.from_row(self)
  end

  def fingerprint
    handshake.fingerprint
  end
end
