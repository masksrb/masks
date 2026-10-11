module Masks
  module Server
    class Group < ApplicationRecord
      include TenantScoped

      KEY = /\A[a-z0-9][a-z0-9._-]*\z/

      has_many :members, class_name: "GroupMember", dependent: :delete_all
      has_many :actors, through: :members

      normalizes :key, with: ->(value) { value.to_s.strip.downcase }
      normalizes :name, with: ->(value) { value.to_s.strip }

      validates :key, presence: true, format: { with: KEY }, length: { maximum: 64 },
                      uniqueness: { scope: :tenant_id }
      validates :name, presence: true, length: { maximum: 100 }

      def add!(actor, by: nil)
        member = members.find_or_create_by!(actor: actor)
        Event.record!(Event::GROUP_JOINED, actor: actor, by: by, group: key) if member.previously_new_record?
        member
      end

      def remove!(actor, by: nil)
        removed = members.where(actor: actor).delete_all.positive?
        Event.record!(Event::GROUP_LEFT, actor: actor, by: by, group: key) if removed
        removed
      end
    end
  end
end
