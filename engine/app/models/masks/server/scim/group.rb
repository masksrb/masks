module Masks
  module Server
    module Scim
      class Group
        MEMBER_PATH = /\Amembers(?:\[\s*value\s+eq\s+"([^"]+)"\s*\])?(?:\.value)?\z/i
        FILTER = /\A\s*(displayName|id)\s+eq\s+"((?:[^"\\]|\\.)*)"\s*\z/i

        attr_reader :organization, :role

        class << self
          def all(organization)
            organization.role_list.map { |role| new(organization, role) }
          end

          def find(organization, id)
            all(organization).find { |group| group.id == id.to_s }
          end

          def filter(groups, expression)
            return groups if expression.blank?

            match = FILTER.match(expression.to_s)

            raise Error.new(:bad_request, "Groups are filtered by displayName or id with eq", scim_type: "invalidFilter") if match.nil?

            attribute, value = match.captures
            wanted = JSON.parse(%("#{value}"))

            groups.select { |group| attribute.casecmp?("id") ? group.id == wanted : group.role.casecmp?(wanted) }
          end
        end

        def initialize(organization, role)
          @organization = organization
          @role = role
        end

        def id
          "#{organization.uuid}.#{role}"
        end

        def built_in?
          Organization::BUILT_IN.include?(role)
        end

        def memberships
          organization.memberships.accepted.where(role: role).includes(:actor).order(:created_at, :id)
        end

        def to_h(base:, members: true)
          {
            "schemas" => [ GROUP ],
            "id" => id,
            "displayName" => role,
            "members" => (listed(base) if members),
            "meta" => {
              "resourceType" => "Group",
              "created" => organization.created_at&.iso8601,
              "lastModified" => organization.updated_at&.iso8601,
              "location" => "#{base}/Groups/#{id}"
            }
          }.compact
        end

        def changes(operations)
          raise Error.new(:bad_request, "a PATCH carries Operations", scim_type: "invalidSyntax") unless operations.is_a?(Array)

          operations.each_with_object({ add: [], remove: [], replace: nil, remove_all: false }) do |operation, held|
            op = operation["op"].to_s.downcase
            path = operation["path"].to_s.strip.presence
            value = operation["value"]

            raise Error.new(:bad_request, "#{operation['op']} is not an operation", scim_type: "invalidSyntax") unless %w[add replace remove].include?(op)

            if path.nil?
              unpathed!(op, value, held)
            elsif (match = MEMBER_PATH.match(path))
              pathed!(op, match[1], value, held)
            elsif path.casecmp?("displayName")
              renamed!(value)
            else
              raise Error.new(:bad_request, "#{path} is not a Group attribute that changes here", scim_type: "noTarget")
            end
          end
        end

        def member_ids(value)
          Array(value.is_a?(Hash) ? [ value ] : value).map do |member|
            uuid = member.is_a?(Hash) ? member["value"] : member

            raise Error.new(:bad_request, "each member names a user by value", scim_type: "invalidValue") if uuid.blank?

            uuid.to_s
          end
        end

        private

          def listed(base)
            memberships.map do |membership|
              { "value" => membership.actor.uuid, "display" => membership.actor.identifier,
                "$ref" => "#{base}/Users/#{membership.actor.uuid}", "type" => "User" }
            end
          end

          def unpathed!(op, value, held)
            raise Error.new(:bad_request, "an operation without a path carries an object", scim_type: "invalidValue") unless value.is_a?(Hash)

            renamed!(value["displayName"]) if value.key?("displayName")

            return unless value.key?("members")

            op == "replace" ? held[:replace] = member_ids(value["members"]) : held[op.to_sym].concat(member_ids(value["members"]))
          end

          def pathed!(op, filtered, value, held)
            case op
            when "add" then held[:add].concat(member_ids(value))
            when "replace" then held[:replace] = member_ids(value)
            when "remove"
              if filtered
                held[:remove] << filtered
              elsif value.nil?
                held[:remove_all] = true
              else
                held[:remove].concat(member_ids(value))
              end
            end
          end

          def renamed!(value)
            return if value.to_s == role

            raise Error.new(:bad_request, "a group is a role, and a role's name does not change", scim_type: "mutability")
          end
      end
    end
  end
end
