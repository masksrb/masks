module Manage
  module Mutations
    class UpdateTenant < BaseMutation
      argument :name, String, required: false
      argument :dynamic_client_scopes, [ String ], required: false
      argument :dynamic_registration, String, required: false
      argument :mail_from, String, required: false
      argument :smtp_address, String, required: false
      argument :smtp_port, Integer, required: false
      argument :smtp_username, String, required: false
      argument :smtp_password, String, required: false
      argument :smtp_authentication, String, required: false
      argument :smtp_domain, String, required: false
      argument :smtp_tls, Boolean, required: false

      field :tenant, Types::TenantType, null: false

      MAIL = %i[
        mail_from smtp_address smtp_port smtp_username smtp_password
        smtp_authentication smtp_domain smtp_tls
      ].freeze

      def resolve(name: nil, dynamic_client_scopes: nil, dynamic_registration: nil, **mail)
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

        MAIL.each do |field|
          next unless mail.key?(field)

          tenant.public_send("#{field}=", mail[field])
        end

        save!(tenant)

        audit!(::Event::TENANT_UPDATED, name: tenant.name, mails: tenant.mails?)

        { tenant: tenant }
      end
    end
  end
end
