module Subjects
  PUBLIC = "public".freeze
  PAIRWISE = "pairwise".freeze
  TYPES = [ PUBLIC, PAIRWISE ].freeze
  UUID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

  class << self
    def for(actor, client)
      return nil if actor.nil?
      return actor.uuid unless client&.pairwise?

      sector = Subject.normalize_value_for(
        :sector, client.sector_identifier.presence || client.client_id
      )

      Subject.find_by(actor_id: actor.id, sector: sector)&.sub ||
        Subject.create!(actor: actor, sector: sector, sub: derive(actor, sector)).sub
    rescue ActiveRecord::RecordNotUnique
      Subject.find_by!(actor_id: actor.id, sector: sector).sub
    end

    def locate(sub)
      return nil if sub.blank?
      return Actor.find_by(uuid: sub) if sub.match?(UUID)

      Actor.joins(:subjects).find_by(subjects: { sub: sub })
    end

    def derive(actor, sector)
      digest = OpenSSL::Digest::SHA256.digest("#{sector}#{actor.uuid}#{actor.tenant.pairwise_salt!}")

      Base64.urlsafe_encode64(digest, padding: false)
    end
  end
end
