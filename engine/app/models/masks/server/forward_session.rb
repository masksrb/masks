module Masks
  module Server
    class ForwardSession < Token
      COOKIE = "masks_forward".freeze

      def self.held(secret, client)
        token = redeem(secret)

        token if token && token.client_id == client.id && token.session&.live? && !token.actor.suspended? &&
                 client.admits?(token.actor)
      end
    end
  end
end
