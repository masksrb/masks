module Manage
  module Mutations
    class UpdateTenant < BaseMutation
      argument :name, String, required: false
      argument :dynamic_client_scopes, [ String ], required: false

      field :tenant, Types::TenantType, null: false

      def resolve(name: nil, dynamic_client_scopes: nil)
        tenant = Current.tenant

        tenant.name = name unless name.nil?

        unless dynamic_client_scopes.nil?
          reserved = Scopes.reserved(dynamic_client_scopes)

          if reserved.any?
            refuse!("#{Scopes.join(reserved)} may not be offered to dynamic registration")
          end

          tenant.dynamic_client_scopes = Scopes.join(dynamic_client_scopes).presence
        end

        { tenant: save!(tenant) }
      end
    end
  end
end
