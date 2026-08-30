module Masks
  module Client
    module Pairing
      PATH = "/setup/connect".freeze

      module_function

      def url(issuer, name:, resource:, redirect_uris:, scope:, return_to:, state:)
        query = [
          [ "client_name", name ],
          [ "resource", resource ],
          [ "scope", Array(scope).join(" ") ],
          [ "return_to", return_to ],
          [ "state", state ]
        ]

        Array(redirect_uris).each { |uri| query << [ "redirect_uris", uri ] }

        "#{Issuer.normalize(url_of(issuer))}#{PATH}?#{URI.encode_www_form(query)}"
      end

      def redeem(issuer, token:, **attributes)
        Registration.create(issuer, token: token, **attributes)
      end

      def url_of(issuer)
        issuer.is_a?(Issuer) ? issuer.url : issuer
      end
    end
  end
end
