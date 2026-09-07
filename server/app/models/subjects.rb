module Subjects
  PUBLIC = "public".freeze
  PAIRWISE = "pairwise".freeze
  TYPES = [ PUBLIC, PAIRWISE ].freeze

  class << self
    def for(actor, client = nil)
      return nil if actor.nil?
      return actor.uuid unless client&.pairwise?

      pairwise(actor, client.sector_identifier.presence || client.client_id)
    end

    def pairwise(actor, sector)
      held = sector.to_s.strip.downcase

      held.present? or raise ArgumentError, "a pairwise subject needs a sector"

      settled(actor, held)
    end

    def locate(sub)
      return nil if sub.blank?

      Actor.find_by(uuid: sub) || Subject.find_by(sub: sub)&.actor
    end

    def derive(actor, sector)
      digest = OpenSSL::Digest::SHA256.digest("#{sector}#{actor.uuid}#{actor.tenant.pairwise_salt!}")

      Base64.urlsafe_encode64(digest, padding: false)
    end

    private

      def settled(actor, sector)
        held = Subject.find_by(actor_id: actor.id, sector: sector)

        return held.sub if held

        Subject.create!(actor: actor, sector: sector, sub: derive(actor, sector)).sub
      rescue ActiveRecord::RecordNotUnique
        Subject.find_by!(actor_id: actor.id, sector: sector).sub
      end
  end
end
