module Masks
  module Server
    module GroupRule
      EMAIL_DOMAIN = "email_domain".freeze
      PROFILE = "profile".freeze
      KINDS = [ EMAIL_DOMAIN, PROFILE ].freeze
      FIELDS = %w[name given_name family_name middle_name nickname gender zoneinfo locale].freeze
      LIMIT = 5
      DOMAIN = /\A[a-z0-9][a-z0-9.-]*\.[a-z]{2,}\z/
      LONGEST = 200

      class << self
        def normalize(value)
          Array(value).filter_map do |condition|
            next unless condition.respond_to?(:to_h)

            held = condition.to_h.to_h { |key, item| [ key.to_s, item.to_s.strip ] }
            kind = held["kind"]
            value = kind == EMAIL_DOMAIN ? held["value"].to_s.downcase.delete_prefix("@") : held["value"].to_s

            { "kind" => kind, "field" => (held["field"] if kind == PROFILE), "value" => value }.compact
          end
        end

        def problems(conditions)
          return [ "a rule has at most #{LIMIT} conditions" ] if conditions.size > LIMIT
          return [ "a rule needs at least one condition" ] if conditions.empty?

          conditions.filter_map { |condition| problem(condition) }
        end

        def scope(conditions)
          conditions.reduce(Actor.all) do |scope, condition|
            case condition["kind"]
            when EMAIL_DOMAIN
              scope.where.not(email_verified_at: nil)
                   .where("LOWER(actors.email) LIKE ?", "%@#{Actor.sanitize_sql_like(condition['value'])}")
            when PROFILE
              scope.merge(Actor.directed).where(condition["field"] => condition["value"])
            else
              scope.none
            end
          end
        end

        private

          def problem(condition)
            case condition["kind"]
            when EMAIL_DOMAIN
              "#{condition['value'].inspect} is not a domain" unless condition["value"].match?(DOMAIN)
            when PROFILE
              return "#{condition['field'].inspect} is not a profile field a rule can read" unless FIELDS.include?(condition["field"])

              "a profile condition needs a value" if condition["value"].blank? || condition["value"].length > LONGEST
            else
              "#{condition['kind'].inspect} is not a kind of condition"
            end
          end
      end
    end
  end
end
