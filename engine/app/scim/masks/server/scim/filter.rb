require "strscan"

module Masks
  module Server
    module Scim
      class Filter
        LONGEST = 512
        TOKEN = /"(?:[^"\\]|\\.)*"|(?:[^\s"\[]|\[[^\]]*\])+/
        PATH = /\A[A-Za-z][\w.:\[\]" ]*\z/
        VALUE = /\A(?:"(?:[^"\\]|\\.)*"|true|false|null|[\d.]+)\z/
        OPERATORS = %w[eq ne co sw ew pr gt ge lt le].freeze
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
          raise Error.new(:bad_request, "a filter is at most #{LONGEST} characters", scim_type: "invalidFilter") if @expression.length > LONGEST

          clauses = clauses_of(tokens)

          raise Error.new(:bad_request, "at most four comparisons joined by and are understood", scim_type: "invalidFilter") if clauses.size > 4

          clauses.reduce(relation) { |held, clause| compare(held, clause) }
        end

        private

          def tokens
            scanner = StringScanner.new(@expression)
            held = []

            until scanner.eos?
              next if scanner.skip(/\s+/)

              token = scanner.scan(TOKEN)

              raise unreadable(@expression) if token.nil?

              held << token
            end

            held
          end

          def clauses_of(tokens)
            clauses = [ [] ]

            tokens.each do |token|
              token.casecmp?("and") ? clauses << [] : clauses.last << token
            end

            clauses
          end

          def unreadable(clause)
            Error.new(:bad_request, "#{clause.strip} is not a filter this server reads", scim_type: "invalidFilter")
          end

          def compare(relation, clause)
            path, operator, raw = clause

            raise unreadable(clause.join(" ")) unless clause.size.between?(2, 3)
            raise unreadable(clause.join(" ")) unless PATH.match?(path) && OPERATORS.include?(operator.downcase)
            raise unreadable(clause.join(" ")) unless raw.nil? || VALUE.match?(raw)

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
            node = attribute(column)
            text = value.to_s
            held = exact ? node : lowered(node)
            wanted = exact ? text : text.downcase
            like = ActiveRecord::Base.sanitize_sql_like(wanted)

            relation.where(
              case operator
              when "eq" then held.eq(wanted)
              when "ne" then node.eq(nil).or(held.not_eq(wanted))
              when "co" then held.matches("%#{like}%", nil, true)
              when "sw" then held.matches("#{like}%", nil, true)
              when "ew" then held.matches("%#{like}", nil, true)
              when "pr" then node.not_eq(nil)
              when "gt" then node.gt(text)
              when "ge" then node.gteq(text)
              when "lt" then node.lt(text)
              when "le" then node.lteq(text)
              end
            )
          end

          def attribute(column)
            table, name = column.split(".")
            Arel::Table.new(table)[name]
          end

          def lowered(node)
            Arel::Nodes::NamedFunction.new("lower", [ Arel::Nodes::NamedFunction.new("CAST", [ node.as("text") ]) ])
          end
      end
    end
  end
end
