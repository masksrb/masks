module Masks
  module Client
    class Introspection < Claims
      def active?
        to_h["active"] == true
      end

      def username
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
          raise Unauthorized.new("the issuer reports this token is not active")
        end

        super
      end
    end
  end
end
