module Masks
  module Server
    module Ldap
      class Gate
        WINDOW = 3.minutes
        VIA = "ldap".freeze

        Bound = Data.define(:kind, :tenant, :dn, :subject) do
          def service?
            kind == :service
          end

          def person?
            kind == :person
          end
        end

        Outcome = Data.define(:code, :message, :bound)

        def initialize(ip_address:)
          @ip_address = ip_address
        end

        def bind(name, password)
          password = password.to_s
          return anonymous if name.blank? && password.empty?
          return refused(Protocol::UNWILLING_TO_PERFORM, "unauthenticated binds are refused") if password.empty?
          return throttled if failures(ip_key) >= ::Rails.configuration.masks.attempt_limit

          dn = parse(name)
          tenant = dn && Directory.tenant_for(dn)

          return decoy(password) if tenant.nil?

          Tenant.switch(tenant) { bind_within(tenant, Directory.new(tenant), dn, password) }
        end

        private

          def anonymous
            Outcome.new(code: Protocol::SUCCESS, message: "", bound: nil)
          end

          def parse(name)
            return Dn.parse(name) if name.include?("=")

            tenant = single_tenant
            tenant && Directory.new(tenant).people_dn.child(:uid, name.strip)
          rescue Dn::Invalid
            nil
          end

          def single_tenant
            return Tenant.active.find_by(subdomain: Tenant.pinned) if Tenant.pinned

            held = Tenant.active.limit(2).to_a
            held.first if held.one?
          end

          def bind_within(tenant, directory, dn, password)
            if dn.parent == directory.services_dn && dn.first_type == "cn"
              service(tenant, directory, dn, password)
            elsif dn.parent == directory.people_dn && dn.first_type == "uid"
              person(tenant, directory, dn.first_value, password)
            else
              decoy(password)
            end
          end

          def service(tenant, directory, dn, password)
            credential = LdapCredential.check(dn.first_value, password)

            if credential.nil?
              failed!(ip_key)
              Event.record!(Event::LOGIN_REFUSED, by: nil, factor: "ldap_service", identifier: dn.first_value, via: VIA)
              return invalid
            end

            credential.used!

            Outcome.new(
              code: Protocol::SUCCESS, message: "",
              bound: Bound.new(kind: :service, tenant: tenant, dn: directory.service_dn(credential.label), subject: credential.id)
            )
          end

          def person(tenant, directory, uid, password)
            account = account_key(tenant, uid)

            if failures(account) >= ::Rails.configuration.masks.account_attempt_limit
              Event.record!(Event::LOGIN_THROTTLED, actor: Actor.locate(uid), by: nil, identifier: uid, via: VIA)
              return throttled
            end

            actor = Actor.authenticate(uid, password)

            if actor.nil?
              failed!(ip_key, account)
              return refuse(uid, "password")
            end

            reason = obstacle(tenant, actor)
            return refuse(uid, reason, actor) if reason

            actor.active!
            dn = directory.person_dn(actor)
            Event.record!(Event::LDAP_BOUND, actor: actor, dn: dn.to_s)

            Outcome.new(code: Protocol::SUCCESS, message: "", bound: Bound.new(kind: :person, tenant: tenant, dn: dn, subject: actor.id))
          end

          def obstacle(tenant, actor)
            return "suspended" if actor.suspended?
            return "pending_approval" if actor.pending_approval_at.present?

            policy = SignInPolicy.for(tenant: tenant)
            return "factor-not-offered" unless policy.first_factor?(:password)
            return nil if tenant.ldap_password_only?

            "second_factor" if second_factor?(policy, actor)
          end

          def second_factor?(policy, actor)
            policy.second_factor_required || policy.apps_require_second_factor ||
              actor.second_factor? || actor.email_factor? || actor.phone_factor?
          end

          def refuse(uid, factor, actor = nil)
            Event.record!(Event::LOGIN_REFUSED, actor: actor || Actor.locate(uid), by: nil, factor: factor, identifier: uid, via: VIA)
            invalid
          end

          def decoy(password)
            BCrypt::Password.new(Actor.decoy_digest) == password
            failed!(ip_key)
            invalid
          end

          def invalid
            refused(Protocol::INVALID_CREDENTIALS, "invalid credentials")
          end

          def throttled
            refused(Protocol::UNWILLING_TO_PERFORM, "too many attempts; wait a few minutes")
          end

          def refused(code, message)
            Outcome.new(code: code, message: message, bound: nil)
          end

          def ip_key
            "ldap-attempts:ip:#{@ip_address}"
          end

          def account_key(tenant, uid)
            "ldap-attempts:#{tenant.id}:#{Digest::SHA256.hexdigest(uid.to_s.strip.downcase)}"
          end

          def failures(key)
            ::Rails.cache.read(key).to_i
          end

          def failed!(*keys)
            keys.each { |key| ::Rails.cache.increment(key, 1, expires_in: WINDOW) }
          end
      end
    end
  end
end
