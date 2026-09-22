module Manage
  module Mutations
    class UpdateTenant < BaseMutation
      argument :name, String, required: false
      argument :dynamic_client_scopes, [ String ], required: false
      argument :dynamic_registration, String, required: false
      argument :named_by, String, required: false
      argument :browsers_only, Boolean, required: false
      argument :blocked_agents, String, required: false
      argument :sign_in_policy, ID, required: false

      field :tenant, Types::TenantType, null: false

      def resolve(name: nil, dynamic_client_scopes: nil, dynamic_registration: nil,
                  named_by: nil, browsers_only: nil, blocked_agents: nil, sign_in_policy: nil)
        tenant = Current.tenant

        tenant.name = name unless name.nil?

        unless named_by.nil?
          refuse!("MASKS_NAMED_BY pins what names an account here") if tenant.names_pinned?

          refuse!("an account is named by a nickname, an email or either") unless
            ::Tenant::NAMES.include?(named_by)

          tenant.named_by = named_by
        end

        unless dynamic_registration.nil?
          if tenant.registration_pinned?
            refuse!("MASKS_DYNAMIC_REGISTRATION pins dynamic registration here")
          end

          unless ::Tenant::REGISTRATIONS.include?(dynamic_registration)
            refuse!("dynamic registration is off, anything or bounded")
          end

          tenant.dynamic_registration = dynamic_registration
        end

        unless dynamic_client_scopes.nil?
          reserved = Scopes.reserved(dynamic_client_scopes)

          if reserved.any?
            refuse!("#{Scopes.join(reserved)} may not be offered to dynamic registration")
          end

          tenant.dynamic_client_scopes = Scopes.join(dynamic_client_scopes).presence
        end

        unless browsers_only.nil?
          refuse!("MASKS_BROWSERS_ONLY pins who may sign in here") if tenant.browsers_pinned?

          tenant.browsers_only = browsers_only
        end

        unless blocked_agents.nil?
          refuse!("MASKS_BLOCKED_AGENTS pins the agents refused here") if tenant.agents_pinned?

          tenant.blocked_agents = blocked_agents.presence
        end

        unless sign_in_policy.nil?
          tenant.sign_in_policy = sign_in_policy.empty? ? nil : sign_in_policy!(sign_in_policy)

          refuse!("#{tenant.sign_in_policy.name} is archived") if tenant.sign_in_policy&.archived?

          if tenant.sign_in_policy && !tenant.sign_in_policy.local?
            refuse!("#{tenant.sign_in_policy.name} offers no password or passkey, so it cannot be the default managers sign in with")
          end
        end

        save!(tenant)

        audit!(::Event::TENANT_UPDATED, name: tenant.name)

        { tenant: tenant }
      end
    end
  end
end
