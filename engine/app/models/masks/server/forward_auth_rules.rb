module Masks
  module Server
    class ForwardAuthRules
      OPEN = "open".freeze
      ONE_FACTOR = "one_factor".freeze
      TWO_FACTOR = "two_factor".freeze
      TOKEN = "token".freeze
      DENY = "deny".freeze
      OUTCOMES = [ OPEN, ONE_FACTOR, TWO_FACTOR, TOKEN, DENY ].freeze

      SIGN_IN = "sign_in".freeze
      DEFAULT = "default".freeze

      METHODS = %w[GET HEAD POST PUT PATCH DELETE OPTIONS].freeze
      LISTS = %w[paths methods networks groups].freeze
      FIELDS = (LISTS + [ "outcome" ]).freeze
      MOST_RULES = 50
      MOST_ENTRIES = 20
      PATH = %r{\A/[^\s?#]{0,511}\z}

      Decision = Struct.new(:outcome, :rule, :index)

      class Rule
        attr_reader :paths, :methods, :networks, :groups, :outcome

        def initialize(held)
          @paths = Array(held["paths"])
          @methods = Array(held["methods"])
          @networks = Array(held["networks"]).filter_map { |range| ForwardAuthRules.network(range) }
          @groups = Array(held["groups"])
          @outcome = held["outcome"].to_s
        end

        def covers?(path, method, address)
          covers_path?(path) && covers_method?(method) && covers_address?(address)
        end

        def gated?
          groups.any?
        end

        def admits?(actor)
          !gated? || actor.group_labels.intersect?(groups)
        end

        private

          def covers_path?(path)
            paths.empty? || patterns.any? { |pattern| pattern.match?(path) }
          end

          def covers_method?(method)
            methods.empty? || methods.include?(method)
          end

          def covers_address?(address)
            return true if networks.empty?

            held = ForwardAuthRules.address(address)
            held.present? && networks.any? { |network| network.include?(held) }
          end

          def patterns
            @patterns ||= paths.map { |path| ForwardAuthRules.pattern(path) }
          end
      end

      class << self
        def normalize(value)
          Array(value).map do |held|
            next held unless held.is_a?(Hash)

            held = held.to_h.transform_keys(&:to_s)
            lists = LISTS.to_h { |list| [ list, Array(held[list]).map { |entry| entry.to_s.strip }.compact_blank.uniq ] }
            lists["methods"] = lists["methods"].map(&:upcase)
            lists["groups"] = lists["groups"].map(&:downcase)

            held.except(*FIELDS).merge(lists, "outcome" => held["outcome"].to_s.strip.downcase)
          end
        end

        def problems(rules)
          return [ "forward auth rules must be a list of rules" ] unless rules.is_a?(Array)
          return [ "forward auth rules hold more than #{MOST_RULES} rules" ] if rules.size > MOST_RULES

          rules.flat_map.with_index(1) { |rule, position| problems_in(rule, position) }
        end

        def pattern(path)
          source = path.split("**", -1).map { |piece| piece.split("*", -1).map { |held| Regexp.escape(held) }.join("[^/]*") }.join(".*")
          source = "#{source.delete_suffix('/.*')}(/.*)?" if path.end_with?("/**")

          /\A#{source}\z/
        end

        def network(range)
          IPAddr.new(range.to_s)
        rescue IPAddr::Error
          nil
        end

        def address(value)
          held = IPAddr.new(value.to_s.split("%").first.to_s)
          held.ipv4_mapped? ? held.native : held
        rescue IPAddr::Error
          nil
        end

        def path(value)
          decoded = URI::RFC2396_PARSER.unescape(value.to_s)
          cleaned = Pathname.new(decoded.start_with?("/") ? decoded : "/#{decoded}").cleanpath.to_s

          cleaned.start_with?("/") ? cleaned : "/"
        end

        private

          def problems_in(rule, position)
            named = "forward auth rule #{position}"
            return [ "#{named} is not a set of fields" ] unless rule.is_a?(Hash)

            unknown = rule.keys - FIELDS
            return [ "#{named} names #{unknown.join(', ')}, which is not a field" ] if unknown.any?

            [
              ("#{named} has an outcome of #{rule['outcome'].inspect}, which is not one of #{OUTCOMES.join(', ')}" unless OUTCOMES.include?(rule["outcome"])),
              *LISTS.map { |list| ("#{named} lists more than #{MOST_ENTRIES} #{list}" if rule[list].size > MOST_ENTRIES) },
              *rule["paths"].grep_v(PATH).map { |path| "#{named} has a path of #{path.inspect}, which does not start with /" },
              *(rule["methods"] - METHODS).map { |method| "#{named} names a method of #{method.inspect}, which is not one of #{METHODS.join(', ')}" },
              *rule["networks"].reject { |range| network(range) }.map { |range| "#{named} has a network of #{range.inspect}, which is not an address or a range such as 192.168.0.0/16" },
              *rule["groups"].grep_v(Client::ALLOWED_GROUP).map { |group| "#{named} names a group of #{group.inspect}, which is not a group key or key:role" }
            ].compact
          end
      end

      attr_reader :rules

      def initialize(held)
        @rules = Array(held).select { |rule| rule.is_a?(Hash) }.map { |rule| Rule.new(rule) }
      end

      def any?
        rules.any?
      end

      def decide(path:, method:, address:, actor: nil)
        cleaned = self.class.path(path)
        verb = method.to_s.upcase.presence || "GET"

        rules.each_with_index do |rule, index|
          next unless rule.covers?(cleaned, verb, address)
          return Decision.new(SIGN_IN, rule, index) if rule.gated? && actor.nil?
          next unless rule.admits?(actor)

          return Decision.new(rule.outcome, rule, index)
        end

        Decision.new(DEFAULT, nil, nil)
      end
    end
  end
end
