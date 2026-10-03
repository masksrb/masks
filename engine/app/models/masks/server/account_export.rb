module Masks
  module Server
    class AccountExport
      PROFILE = %i[
        nickname name given_name middle_name family_name email phone profile_url picture_url website_url
        gender birthdate zoneinfo locale
      ].freeze
      MOMENTS = %i[
        created_at signed_up_at activated_at email_verified_at phone_verified_at last_login_at last_active_at
        suspended_at
      ].freeze

      attr_reader :actor, :tenant

      def initialize(actor, tenant: Current.tenant)
        @actor = actor
        @tenant = tenant
      end

      def filename
        "#{tenant.subdomain}-#{actor.identifier.to_s.parameterize.presence || 'account'}-#{Date.current.iso8601}.json"
      end

      def to_json(*)
        JSON.pretty_generate(as_json)
      end

      def as_json(*)
        {
          "exported_at" => moment(Time.current),
          "tenant" => tenant.subdomain,
          "account" => account,
          "factors" => factors,
          "passkeys" => passkeys,
          "organizations" => organizations,
          "connections" => connections,
          "apps" => apps,
          "devices" => devices,
          "events" => events
        }
      end

      private

        def moment(value)
          value&.utc&.iso8601
        end

        def account
          PROFILE.to_h { |field| [ field.to_s, actor.public_send(field) ] }
                 .merge(MOMENTS.to_h { |field| [ field.to_s, moment(actor.public_send(field)) ] })
                 .merge("uuid" => actor.uuid, "suspension_reason" => actor.suspension_reason)
                 .compact
        end

        def factors
          {
            "password" => actor.password_digest.present?,
            "authenticator_app" => moment(actor.otp_enabled_at),
            "backup_codes" => moment(actor.backup_codes_generated_at),
            "email_codes" => moment(actor.email_factor_at),
            "text_message_codes" => moment(actor.phone_factor_at)
          }.compact
        end

        def passkeys
          Passkey.where(actor: actor).includes(:authenticator).order(:created_at).map do |passkey|
            {
              "name" => passkey.label,
              "created_at" => moment(passkey.created_at),
              "last_used_at" => moment(passkey.last_used_at)
            }.compact
          end
        end

        def organizations
          actor.memberships.includes(:organization).order(:created_at).map do |membership|
            {
              "organization" => membership.organization.name,
              "key" => membership.organization.key,
              "role" => membership.role,
              "pending" => membership.pending,
              "joined_at" => moment(membership.created_at)
            }
          end
        end

        def connections
          Connection.where(actor: actor).includes(:provider, delegations: :client).order(:created_at).map do |connection|
            {
              "provider" => connection.provider.name,
              "subject" => connection.subject,
              "email" => connection.email,
              "connected_at" => moment(connection.connected_at || connection.created_at),
              "signed_in_at" => moment(connection.signed_in_at),
              "revoked_at" => moment(connection.revoked_at),
              "delegations" => connection.delegations.map do |delegation|
                {
                  "app" => delegation.client.name,
                  "scopes" => Scopes.list(delegation.scopes),
                  "consented_at" => moment(delegation.consented_at),
                  "revoked_at" => moment(delegation.revoked_at)
                }.compact
              end
            }.compact
          end
        end

        def apps
          Consent.where(actor: actor).includes(:client).order(:created_at).map do |consent|
            {
              "app" => consent.client.name,
              "client_id" => consent.client.client_id,
              "scopes" => Scopes.list(consent.scopes),
              "granted_at" => moment(consent.created_at),
              "revoked_at" => moment(consent.revoked_at)
            }.compact
          end
        end

        def devices
          trusted = DeviceFactor.live.where(actor: actor).pluck(:device_id).to_set

          actor.devices.map do |device|
            {
              "name" => device.name,
              "user_agent" => device.user_agent,
              "ip_address" => device.ip_address,
              "first_seen_at" => moment(device.created_at),
              "last_seen_at" => moment(device.last_seen_at),
              "trusted" => trusted.include?(device.id),
              "blocked_at" => moment(device.blocked_at)
            }.compact
          end
        end

        def events
          Event.where(actor: actor)
               .includes(:actor, :by, :client, :organization).order(:created_at, :id)
               .map { |event| event.exported(tenant).except(:tenant, :id) }
        end
    end
  end
end
