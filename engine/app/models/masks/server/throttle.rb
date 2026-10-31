module Masks
  module Server
    module Throttle
      class Invalid < StandardError; end

      Budget = Struct.new(:name, :to, :within, :about, :variable, keyword_init: true) do
        def key
          name.to_s
        end

        def limits
          { to: to, within: within }
        end

        def reference
          "| `#{variable}` | `#{key}` | #{to} in #{within.inspect} | #{about} |"
        end
      end

      DEFAULTS = [
        Budget.new(name: :attempt, to: 10, within: 3.minutes, variable: "MASKS_ATTEMPT_LIMIT",
                   about: "Sign-in attempts from one IP address. Includes sign-in through a provider, failed LDAP binds, and app passwords."),
        Budget.new(name: :account_attempt, to: 5, within: 3.minutes, variable: "MASKS_ACCOUNT_ATTEMPT_LIMIT",
                   about: "Sign-in attempts against one account, from any IP address. Includes failed LDAP binds and app passwords. " \
                          "Also how often a signed-in account changes its password, email address, or phone number, adds an " \
                          "authenticator app, or approves a sign-in on another device."),
        Budget.new(name: :recovery, to: 5, within: 15.minutes, variable: "MASKS_RECOVERY_LIMIT",
                   about: "Codes and links sent by email or text message. Counted by IP address during sign-in, and by account for " \
                          "every address or phone number a code goes to, including a phone added or changed during sign-in."),
        Budget.new(name: :registration, to: 10, within: 10.minutes, variable: "MASKS_REGISTRATION_LIMIT",
                   about: "Dynamic client registrations from one IP address, and new client metadata documents."),
        Budget.new(name: :device_code, to: 30, within: 3.minutes, variable: "MASKS_DEVICE_CODE_LIMIT",
                   about: "Device user codes entered from one IP address."),
        Budget.new(name: :claim, to: 3, within: 1.hour, variable: "MASKS_CLAIM_LIMIT",
                   about: "Tenants claimed from one IP address, when a subdomain template claims a tenant on its first visit. " \
                          "Counted across the whole server."),
        Budget.new(name: :claim_ceiling, to: 30, within: 1.hour, variable: "MASKS_CLAIM_CEILING",
                   about: "Tenants claimed from all IP addresses together, under the same template. Counted across the whole server."),
        Budget.new(name: :token, to: 60, within: 1.minute, variable: "MASKS_TOKEN_LIMIT", about: "Token requests from one IP address."),
        Budget.new(name: :pushed_authorization, to: 60, within: 1.minute, variable: "MASKS_PUSHED_AUTHORIZATION_LIMIT", about: "Pushed authorization requests from one IP address."),
        Budget.new(name: :device_authorization, to: 60, within: 1.minute, variable: "MASKS_DEVICE_AUTHORIZATION_LIMIT", about: "Device authorization requests from one IP address."),
        Budget.new(name: :introspection, to: 120, within: 1.minute, variable: "MASKS_INTROSPECTION_LIMIT", about: "Token introspections from one IP address."),
        Budget.new(name: :revocation, to: 120, within: 1.minute, variable: "MASKS_REVOCATION_LIMIT", about: "Token revocations from one IP address."),
        Budget.new(name: :saml, to: 60, within: 1.minute, variable: "MASKS_SAML_LIMIT", about: "SAML sign-in and logout requests from one IP address."),
        Budget.new(name: :forward_auth, to: 30, within: 1.minute, variable: "MASKS_FORWARD_AUTH_LIMIT", about: "Forward auth sign-ins started or finished from one IP address."),
        Budget.new(name: :enrollment, to: 30, within: 1.minute, variable: "MASKS_ENROLLMENT_LIMIT", about: "Enrollment tokens redeemed from one IP address."),
        Budget.new(name: :app_enrollment, to: 60, within: 1.hour, variable: "MASKS_APP_ENROLLMENT_LIMIT", about: "Enrollment tokens one app mints."),
        Budget.new(name: :invitation, to: 30, within: 1.minute, variable: "MASKS_INVITATION_LIMIT", about: "Organization invitations one account sends or sends again."),
        Budget.new(name: :export, to: 5, within: 1.hour, variable: "MASKS_EXPORT_LIMIT", about: "Account exports one account asks for."),
        Budget.new(name: :access_request, to: 1, within: 1.hour, variable: "MASKS_ACCESS_REQUEST_LIMIT", about: "Times one account asks for access to one app."),
        Budget.new(name: :signal, to: 600, within: 1.minute, variable: "MASKS_SIGNAL_LIMIT", about: "Security events received from one IP address."),
        Budget.new(name: :scim, to: 600, within: 1.minute, variable: "MASKS_SCIM_LIMIT", about: "SCIM provisioning requests from one IP address.")
      ].freeze

      NAMES = DEFAULTS.map(&:key).freeze

      module_function

      def budgets
        @budgets ||= DEFAULTS.to_h { |budget| [ budget.name, budget.dup.tap { |held| held.to = limit_for(budget) } ] }
      end

      def budget(name)
        budgets.fetch(name.to_sym) { raise Invalid, "no limit is called #{name}. The limits are #{NAMES.join(', ')}." }
      end

      def limit(name)
        budget(name).to
      end

      def limits(name)
        budget(name).limits
      end

      def refused(name, &block)
        held = budget(name)

        proc { Throttle.hit!(held.name); instance_exec(&block) }
      end

      def key(name, by, scope: nil, named: nil)
        held = budget(name)

        [ "rate-limit", scope || "masks/server/#{held.key}", named, by ].compact.join(":")
      end

      def count!(name, by, scope: nil, named: nil)
        ::Rails.cache.increment(key(name, by, scope: scope, named: named), 1, expires_in: budget(name).within)
      end

      def exceeded?(name, by, scope: nil, named: nil, times: 1)
        ::Rails.cache.read(key(name, by, scope: scope, named: named)).to_i >= budget(name).to * times
      end

      def crowded?(name, by, scope: nil, named: nil, times: 1)
        held = budget(name)

        ::Rails.cache.increment(key(name, by, scope: scope, named: named), 1, expires_in: held.within).to_i > held.to * times
      end

      def hit!(name, actor: nil, client: nil, address: Current.ip_address, **details)
        held = budget(name)

        ::Rails.logger.info("masks: the #{held.key} limit of #{held.to} in #{held.within.inspect} was reached" \
                            "#{address.present? ? " from #{address}" : ''}")

        return if Current.tenant.nil?
        return unless ::Rails.cache.write(key(name, "reached:#{address}"), true, unless_exist: true, expires_in: held.within)

        Event.record!(Event::LIMIT_REACHED, actor: actor, by: nil, client: client, limit: held.key, **details)
      end

      def reference
        DEFAULTS.map(&:reference)
      end

      def reset!
        @budgets = nil
        @declared = nil
      end

      def limit_for(budget)
        from_env(budget) || declared.fetch(budget.key, nil) || budget.to
      end

      def from_env(budget)
        value = ENV[budget.variable]

        return nil if value.blank?

        whole!(value, budget.variable)
      end

      def declared
        @declared ||= read_declared(::Rails.configuration.masks.config_path)
      end

      def read_declared(path)
        return {} if path.blank?

        document = YAML.safe_load_file(path, aliases: false) || {}
        limits = document.is_a?(Hash) ? document.fetch("limits", nil) || {} : {}

        raise Invalid, "limits in #{path} must map each limit's name to a whole number" unless limits.is_a?(Hash)

        unknown = limits.keys.map(&:to_s) - NAMES
        raise Invalid, "#{path} sets limits called #{unknown.join(', ')}, which do not exist. The limits are #{NAMES.join(', ')}." if unknown.any?

        limits.to_h { |name, value| [ name.to_s, whole!(value, "limits.#{name} in #{path}") ] }
      rescue Errno::ENOENT, Psych::Exception
        {}
      end

      def whole!(value, where)
        count = Integer(value.to_s, 10)

        raise Invalid, "#{where} is #{value.inspect}. A limit is a whole number, 1 or more." if count < 1

        count
      rescue ArgumentError, TypeError
        raise Invalid, "#{where} is #{value.inspect}. A limit is a whole number, 1 or more."
      end
    end
  end
end
