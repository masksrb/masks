module Masks
  module Client
    class Introspection < Claims
      def active?
        to_h["active"] == true
      end

      def nickname
        self["username"]
      end

      def token_type
        self["token_type"]
      end

      def permits?(scope)
        active? && super
      end

      def permit!(scope)
        unless active?
          raise Unauthorized.new(Masks::Client.saying("not_active"))
        end

        super
      end

      def member!(*roles, organization: nil)
        raise Unauthorized.new(Masks::Client.saying("not_active")) unless active?

        super
      end
    end
  end
end
