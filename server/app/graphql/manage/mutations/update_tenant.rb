module Manage
  module Mutations
    class UpdateTenant < BaseMutation
      argument :name, String, required: false
      argument :dynamic_client_scopes, [ String ], required: false
      argument :dynamic_registration, String, required: false

      field :tenant, Types::TenantType, null: false

      def resolve(name: nil, dynamic_client_scopes: nil, dynamic_registration: nil)
        tenant = Current.tenant

        tenant.name = name unless name.nil?

        unless dynamic_registration.nil?
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

        save!(tenant)

        audit!(::Event::TENANT_UPDATED, name: tenant.name)

        { tenant: tenant }
      end
    end
  end
end
