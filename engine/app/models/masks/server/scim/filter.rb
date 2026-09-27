module Masks
  module Server
    module Scim
      class Filter
        COMPARISON = /\A\s*([A-Za-z][\w.:\[\]" -]*?)\s+(eq|ne|co|sw|ew|pr|gt|ge|lt|le)(?:\s+("(?:[^"\\]|\\.)*"|true|false|null|[\d.]+))?\s*\z/i
        ATTRIBUTES = {
          "id" => "actors.uuid",
          "username" => :user_name,
          "externalid" => "actors.external_id",
          "emails" => "actors.email",
          "emails.value" => "actors.email",
          "displayname" => "actors.name",
          "name.givenname" => "actors.given_name",
          "name.familyname" => "actors.family_name",
          "active" => :active,
          "meta.created" => "actors.created_at",
          "meta.lastmodified" => "actors.updated_at"
        }.freeze
        CASE_EXACT = %w[externalid].freeze

        def self.apply(relation, expression, columns: {})
          return relation if expression.blank?

          new(expression, columns: columns).apply(relation)
        end

        def initialize(expression, columns: {})
          @expression = expression.to_s
          @columns = ATTRIBUTES.merge(columns)
        end

        def apply(relation)
          clauses = @expression.split(/\s+and\s+/i)

          raise Error.new(:bad_request, "at most four comparisons joined by and are understood", scim_type: "invalidFilter") if clauses.size > 4

          clauses.reduce(relation) { |held, clause| compare(held, clause) }
        end

        private

          def compare(relation, clause)
            match = COMPARISON.match(clause)

            raise Error.new(:bad_request, "#{clause.strip} is not a filter this server reads", scim_type: "invalidFilter") if match.nil?

            path, operator, raw = match.captures
            key = normalized(path)
            column = @columns[key]
            operator = operator.downcase

            raise Error.new(:bad_request, "#{path} cannot be filtered on", scim_type: "invalidFilter") if column.nil?

            value = literal(raw)

            case column
            when :user_name then user_name(relation, operator, value)
            when :active then active(relation, operator, value)
            else column_compare(relation, column, operator, value, exact: CASE_EXACT.include?(key))
            end
          end

          def normalized(path)
            path.to_s.downcase.sub(/\Aurn:ietf:params:scim:schemas:core:2\.0:user:/, "").sub(/\[type eq "work"\]|\[primary eq true\]/, "")
          end

          def literal(raw)
            return nil if raw.nil? || raw == "null"
            return raw == "true" if %w[true false].include?(raw)
            return JSON.parse(raw) if raw.start_with?('"')

            raw
          rescue JSON::ParserError
            raise Error.new(:bad_request, "#{raw} is not a value this server reads", scim_type: "invalidFilter")
          end

          def user_name(relation, operator, value)
            raise Error.new(:bad_request, "userName is filtered with eq", scim_type: "invalidFilter") unless operator == "eq"

            wanted = value.to_s.strip
            relation.where("lower(actors.nickname) = :wanted OR lower(actors.email) = :wanted", wanted: wanted.downcase)
          end

          def active(relation, operator, value)
            raise Error.new(:bad_request, "active is filtered with eq", scim_type: "invalidFilter") unless operator == "eq"

            value ? relation.where(suspended_at: nil) : relation.where.not(suspended_at: nil)
          end

          def column_compare(relation, column, operator, value, exact:)
            text = value.to_s
            held = exact ? column : "lower(#{column}::text)"
            wanted = exact ? text : text.downcase
            like = ActiveRecord::Base.sanitize_sql_like(wanted)

            case operator
            when "eq" then relation.where("#{held} = ?", wanted)
            when "ne" then relation.where("#{column} IS NULL OR #{held} <> ?", wanted)
            when "co" then relation.where("#{held} LIKE ?", "%#{like}%")
            when "sw" then relation.where("#{held} LIKE ?", "#{like}%")
            when "ew" then relation.where("#{held} LIKE ?", "%#{like}")
            when "pr" then relation.where("#{column} IS NOT NULL")
            when "gt" then relation.where("#{column} > ?", text)
            when "ge" then relation.where("#{column} >= ?", text)
            when "lt" then relation.where("#{column} < ?", text)
            when "le" then relation.where("#{column} <= ?", text)
            end
          end
      end
    end
  end
end
