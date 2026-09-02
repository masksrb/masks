class Invitation < Token
  class Refused < StandardError; end

  def self.lifetime
    Rails.configuration.masks.invitation_lifetime
  end

  def self.open!(actor:, invited_by: nil)
    raise Refused, "#{actor.nickname} has already accepted an invitation" if actor.activated?

    where(actor_id: actor.id).live.find_each(&:consume!)

    mint!(actor: actor, payload: { "invited_by" => invited_by&.uuid }.compact)
  end

  def self.accept!(secret, password)
    claimed = claim(secret)
    return nil if claimed.nil?

    claimed.actor.activate!(password, verifying_email: claimed.delivered?)
    claimed.actor
  end

  def invited_by
    uuid = (payload || {})["invited_by"]

    @invited_by ||= uuid && Actor.find_by(uuid: uuid)
  end

  def url(origin)
    "#{origin}/invite/#{secret}"
  end

  def delivered!
    update!(payload: (payload || {}).merge("delivered" => true))
  end

  def delivered?
    (payload || {})["delivered"].present?
  end
end
