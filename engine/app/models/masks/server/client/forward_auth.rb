module Masks
  module Server
    class Client
      module ForwardAuth
        extend ActiveSupport::Concern

        included do
          validate :forward_is_described, if: :forward?
          validate :forward_auth_rules_are_usable

          normalizes :forward_auth_rules, with: ->(value) { ForwardAuthRules.normalize(value) }
        end

        class_methods do
          def forwarding_to(uri)
            origin = Forwarded.origin(uri)
            return nil if origin.nil?

            speaking(FORWARD).approved.where("redirect_uris @> ?", [ "#{origin}#{FORWARD_CALLBACK}" ].to_json).first
          end
        end

        def forward?
          protocol == FORWARD
        end

        def forward_origin
          Forwarded.origin(redirect_uris.first) if forward?
        end

        def forward_rules
          ForwardAuthRules.new(forward_auth_rules)
        end

        private

          def forward_is_described
            errors.add(:grant_types, "are not used by an app behind a proxy") if grant_types.any?
            errors.add(:token_endpoint_auth_method, "is none for an app behind a proxy") unless public?

            unless redirect_uris.one? && redirect_uris.first.to_s.end_with?(FORWARD_CALLBACK) && forward_origin
              errors.add(:redirect_uris, "hold the app's own #{FORWARD_CALLBACK}, and nothing else")
            end
          end

          def forward_auth_rules_are_usable
            held = forward_auth_rules

            return errors.add(:base, "forward auth rules apply only to an app behind a proxy") if held.present? && !forward?

            ForwardAuthRules.problems(held).each { |problem| errors.add(:base, problem) }
          end
      end
    end
  end
end
