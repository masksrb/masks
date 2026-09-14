class ProvisioningToken < Token
  LONGEST = 1.year

  def self.lifetime
    LONGEST
  end

  def self.issue!(label:, by:, expires_in: nil)
    lifetime = [ expires_in&.seconds || LONGEST, LONGEST ].min

    mint!(
      payload: { "label" => label.to_s.strip.presence || "Provisioning", "issued_by" => by&.uuid }.compact,
      expires_at: lifetime.from_now
    )
  end

  def label
    held("label")
  end

  def issued_by
    Actor.find_by(uuid: held("issued_by")) if held("issued_by")
  end

  def used_at
    held("used_at")&.then { |value| Time.zone.parse(value) }
  end

  def used!
    return if used_at && used_at > 5.minutes.ago

    update_columns(payload: (payload || {}).merge("used_at" => Time.current.iso8601))
  end
end
