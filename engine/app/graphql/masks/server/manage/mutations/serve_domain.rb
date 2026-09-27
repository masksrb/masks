module Masks
  module Server
    module Manage
      module Mutations
        class ServeDomain < BaseMutation
          requires :owner

          description "Serves sign-in from a host within a proven domain, such as login.example.com, or stops " \
                      "when host is null. The host is a second issuer, so apps that use it must name it."

          argument :host, String, required: false

          field :tenant, Types::TenantType, null: false

          def resolve(host: nil)
            tenant = Current.tenant
            was = tenant.custom_host
            tenant.custom_host = host

            save!(tenant)

            if tenant.custom_host
              audit!(Masks::Server::Event::CUSTOM_DOMAIN_SERVED, host: tenant.custom_host, was: was)
            elsif was
              audit!(Masks::Server::Event::CUSTOM_DOMAIN_STOPPED, host: was, reason: "stopped")
            end

            { tenant: tenant }
          end
        end
      end
    end
  end
end
