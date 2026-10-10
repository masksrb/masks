module Masks
  module Server
    class InitialAccessToken < Token
      def return_to
        redirect_uri
      end

      def issue!
        client.issue_credentials! unless held("keeping")
        client
      end
    end
  end
end
