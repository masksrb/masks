module Masks
  module Server
    module Manage
      module Mutations
        class SetProviderOrganization < BaseMutation
          requires :security

          description "Hands a provider to one organization, or back to the whole tenant. People who sign in " \
                      "through it become members, in the role their groups map to."

          argument :key, ID
          argument :organization, ID, required: false, description: "An organization's key, or null for the whole tenant."
          argument :role_claim, String, required: false
          argument :role_map, GraphQL::Types::JSON, required: false
          argument :unmapped_role, String, required: false

          field :provider, Types::ProviderType, null: false

          def resolve(key:, organization: nil, role_claim: nil, role_map: nil, unmapped_role: nil)
            provider = provider!(key)

            provider.organization = organization && (Masks::Server::Organization.active.find_by(key: organization) ||
              refuse!("no organization keyed #{organization}"))
            provider.role_claim = role_claim.presence
            provider.role_map = provider.organization ? mapped(role_map) : {}
            provider.unmapped_role = provider.organization ? unmapped_role.presence : nil

            save!(provider)

            audit!(Masks::Server::Event::PROVIDER_UPDATED, provider: provider.key, organization: provider.organization&.key,
                                                          changed: [ "organization" ])

            { provider: provider }
          end

          private

            def mapped(value)
              held = value.respond_to?(:to_h) ? value.to_h : {}

              refuse!("roleMap maps group names to role names") unless held.all? { |group, role| group.present? && role.is_a?(String) }

              held.transform_keys(&:to_s)
            end
        end
      end
    end
  end
end
