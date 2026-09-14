module Scim
  class Filter
    COMPARISON = /\A\s*([A-Za-z][\w.:\[\]" -]*?)\s+(eq|ne|co|sw|ew|pr|gt|ge|lt|le)(?:\s+("(?:[^"\\]|\\.)*"|true|false|null|[\d.]+))?\s*\z/i
    ATTRIBUTES = {
      "id" => "uuid",
      "username" => :user_name,
      "externalid" => "external_id",
      "emails" => "email",
      "emails.value" => "email",
      "displayname" => "name",
      "name.givenname" => "given_name",
      "name.familyname" => "family_name",
      "active" => :active,
      "meta.created" => "created_at",
      "meta.lastmodified" => "updated_at"
    }.freeze

    def self.apply(relation, expression)
      return relation if expression.blank?

      new(expression).apply(relation)
    end

    def initialize(expression)
      @expression = expression.to_s
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
        column = ATTRIBUTES[normalized(path)]
        operator = operator.downcase

        raise Error.new(:bad_request, "#{path} cannot be filtered on", scim_type: "invalidFilter") if column.nil?

        value = literal(raw)

        case column
        when :user_name then user_name(relation, operator, value)
        when :active then active(relation, operator, value)
        else column_compare(relation, column, operator, value)
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

      def column_compare(relation, column, operator, value)
        quoted = relation.connection.quote_column_name(column)
        table = "actors.#{quoted}"
        text = value.to_s
        like = ActiveRecord::Base.sanitize_sql_like(text.downcase)

        case operator
        when "eq" then relation.where("lower(#{table}::text) = ?", text.downcase)
        when "ne" then relation.where("#{table} IS NULL OR lower(#{table}::text) <> ?", text.downcase)
        when "co" then relation.where("lower(#{table}::text) LIKE ?", "%#{like}%")
        when "sw" then relation.where("lower(#{table}::text) LIKE ?", "#{like}%")
        when "ew" then relation.where("lower(#{table}::text) LIKE ?", "%#{like}")
        when "pr" then relation.where.not(column => nil)
        when "gt" then relation.where("#{table} > ?", text)
        when "ge" then relation.where("#{table} >= ?", text)
        when "lt" then relation.where("#{table} < ?", text)
        when "le" then relation.where("#{table} <= ?", text)
        end
      end
  end
end
