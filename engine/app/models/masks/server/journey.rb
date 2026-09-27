module Masks
  module Server
    class Journey
      SIGN_IN = "sign_in".freeze
      ACCOUNT = "account".freeze
      MANAGE = "manage".freeze
      SYSTEM = "system".freeze

      AUTHORIZATION = "authorization".freeze
      DEVICE = "device".freeze
      SAML = "saml".freeze

      LOGO = 88

      attr_reader :kind, :via, :client, :by, :origin

      class << self
        def sign_in(login)
          request = login.request

          new(kind: SIGN_IN, client: login.client, via: request && via_for(request))
        end

        def account(actor)
          new(kind: ACCOUNT, by: actor)
        end

        def manage(by)
          new(kind: MANAGE, by: by)
        end

        def system(origin: nil)
          new(kind: SYSTEM, origin: origin)
        end

        def load(held)
          new(
            kind: held["kind"], via: held["via"], origin: held["origin"],
            client: GlobalID::Locator.locate(held["client"]), by: GlobalID::Locator.locate(held["by"])
          )
        end

        private

          def via_for(request)
            return DEVICE if request.device?
            return SAML if request.saml?

            AUTHORIZATION
          end
      end

      def initialize(kind:, via: nil, client: nil, by: nil, origin: nil)
        @kind = kind
        @via = via
        @client = client
        @by = by
        @origin = origin.presence || Current.origin.presence || Current.tenant&.public_origin
      end

      def dump
        {
          "kind" => kind, "via" => via, "origin" => origin,
          "client" => client&.to_global_id&.to_s, "by" => by&.to_global_id&.to_s
        }
      end

      def tenant_name
        Current.tenant&.name
      end

      def branded?
        client.present? && client.approved?
      end

      def heading
        branded? ? client.name : tenant_name
      end

      def logo_url
        return nil unless branded? && client.logo_digest.present? && origin.present?

        "#{origin}#{Engine.routes.url_helpers.client_logo_path(client.client_id, v: client.logo_digest, size: LOGO)}"
      end

      def manager
        by if kind == MANAGE
      end
    end
  end
end
