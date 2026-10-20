module Masks
  module Server
    module Manage
      module Mutations
        module GroupSource
          extend ActiveSupport::Concern

          included do
            argument :source, String, required: false,
                     description: "manual, rule, provider, or group. A sourced group fills itself and keeps anyone added by hand."
            argument :rule, [ Types::GroupConditionInput ], required: false,
                     description: "For rule: up to five conditions, all of which must hold."
            argument :provider_key, String, required: false, description: "For provider: the provider whose sign-ins list groups."
            argument :upstream_group, String, required: false, description: "For provider: the group name the provider lists."
            argument :parent_labels, [ String ], required: false,
                     description: "For group: group keys and organization roles, as key:role, the group holds everyone from."
          end

          private

            def fill_source(group, source: nil, rule: nil, provider_key: nil, upstream_group: nil, parent_labels: nil)
              group.source = source unless source.nil?
              group.rule = rule.map(&:to_h) unless rule.nil?
              group.provider = provider_key.blank? ? nil : provider!(provider_key) unless provider_key.nil?
              group.upstream_group = upstream_group unless upstream_group.nil?
              group.parent_labels = parent_labels unless parent_labels.nil?

              group
            end
        end
      end
    end
  end
end
