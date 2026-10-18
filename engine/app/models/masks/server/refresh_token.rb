module Masks
  module Server
    class RefreshToken < Token
      def self.lifetime
        30.days
      end

      def self.absolute_lifetime
        90.days
      end

      def exhausted?(limit)
        root.created_at + limit <= Time.current
      end

      def self.mint!(**attributes)
        super.tap { |token| token.actor&.active! }
      end

      def revoke!
        transaction do
          super + family.where(kind: AccessToken.sti_name).live.update_all(consumed_at: Time.current, updated_at: Time.current)
        end
      end
    end
  end
end
