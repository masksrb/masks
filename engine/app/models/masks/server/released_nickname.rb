module Masks
  module Server
    class ReleasedNickname < ApplicationRecord
      include TenantScoped

      HOLD = 30.days

      belongs_to :actor, optional: true

      scope :holding, ->(nickname) { where(nickname: nickname.to_s.downcase).where("released_at > ?", HOLD.ago) }
      scope :lapsed, -> { where(released_at: ...HOLD.ago) }

      class << self
        def release!(nickname, actor:)
          return if nickname.blank?

          find_or_initialize_by(nickname: nickname.downcase).update!(actor: actor, released_at: Time.current)
        end

        def held_from?(nickname, actor)
          holding(nickname).where.not(actor_id: actor.id).or(holding(nickname).where(actor_id: nil)).exists?
        end
      end
    end
  end
end
