module Masks
  module Server
    module LoginStates
      class OrganizationChoice < LoginState
        FACTOR = "organization".freeze
        EXPIRY = 1.hour

        accepts :organization

        def enabled?
          request.present? && actor.present? && login.first_factored? && wanted?
        end

        handles "organization" do
          choose!(update(:organization))
        end

        prompts "choose-organization" do
          selected.nil?
        end

        def factor!
          if enabled?
            settle_without_asking!

            super
          end

          hold_to_policy!
        end

        def as_json
          return {} if selected

          {
            "organizations" => memberships.map do |membership|
              { "key" => membership.organization.key, "name" => membership.organization.name, "role" => membership.role }
            end
          }
        end

        def selected
          return nil unless enabled?

          key = chosen_key

          key && memberships.find { |membership| membership.organization.key == key }&.organization
        end

        def chosen_key
          held = login.store.dig("factors", FACTOR)

          held["key"] if held.is_a?(Hash) && held["rid"] == login.rid.to_s && touched?(FACTOR)
        end

        def start_over!
          expire! FACTOR
        end

        def reload!
          @memberships = nil
        end

        private

          def wanted?
            request.organization_key.present? || request.scopes_for(actor).include?(Scopes::ORGANIZATION)
          end

          def memberships
            @memberships ||= actor.memberships.live.to_a
          end

          def hold_to_policy!
            return if login.organization.nil?

            if login.organization_refuses?
              refuse!("access_denied", "#{login.organization.name} does not admit this account's address")
            end

            return unless login.organization_unsatisfied?

            warn! "organization-sign-in"
            prompt! "first-factor"
          end

          def settle_without_asking!
            return if selected

            named = request.organization_key

            return choose!(named) if named
            return refuse!("access_denied", "#{actor.identifier} belongs to no organization") if memberships.empty?

            choose!(memberships.first.organization.key) if memberships.one?
          end

          def choose!(key)
            membership = memberships.find { |held| held.organization.key == key.to_s }

            refuse!("access_denied", "#{actor.identifier} is not a member of #{key}") if membership.nil?

            factored!(FACTOR, expiry: EXPIRY).merge!("rid" => login.rid.to_s, "key" => membership.organization.key)
          end
      end
    end
  end
end
