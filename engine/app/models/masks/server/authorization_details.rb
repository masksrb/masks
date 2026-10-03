module Masks
  module Server
    class AuthorizationDetails
      class Invalid < StandardError; end

      ENTRY_LIMIT = 10
      BYTE_LIMIT = 8.kilobytes
      TYPE_FORMAT = /\A[A-Za-z0-9_.:\/-]{1,200}\z/
      SCHEMA_KEYWORDS = %w[type properties required additionalProperties items enum maxLength maxItems minimum maximum
                           title description].freeze
      SCHEMA_TYPES = %w[object array string number integer boolean].freeze
      LABEL_LIMIT = 100

      include Enumerable

      attr_reader :entries

      class << self
        def parse(value)
          return nil if value.blank?

          held = value.is_a?(String) ? JSON.parse(value) : value
          held = held.map { |entry| entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry } if held.is_a?(Array)

          raise Invalid, "authorization_details must be a JSON array" unless held.is_a?(Array)
          raise Invalid, "authorization_details holds no entries" if held.empty?
          raise Invalid, "authorization_details holds more than #{ENTRY_LIMIT} entries" if held.size > ENTRY_LIMIT
          raise Invalid, "authorization_details is larger than #{BYTE_LIMIT / 1.kilobyte}KB" if held.to_json.bytesize > BYTE_LIMIT

          new(held.map { |entry| entry!(entry) })
        rescue JSON::ParserError
          raise Invalid, "authorization_details is not JSON"
        end

        def declared
          Client.active.approved.where.not(authorization_details_schemas: {})
                .each_with_object({}) do |client, held|
                  client.authorization_details_schemas.each { |type, declaration| held[type] ||= declaration }
                end
        end

        def supported_types
          declared.keys.sort
        end

        def check_declaration!(declarations)
          raise Invalid, "must map each type to its declaration" unless declarations.is_a?(Hash)

          declarations.each do |type, declaration|
            raise Invalid, "#{type.to_s.truncate(40).inspect} is not a type name" unless type.to_s.match?(TYPE_FORMAT)
            raise Invalid, "#{type} must be declared as an object" unless declaration.is_a?(Hash)

            label = declaration["label"]
            raise Invalid, "#{type} needs a label of at most #{LABEL_LIMIT} characters" unless label.is_a?(String) && label.present? && label.length <= LABEL_LIMIT

            schema = declaration["schema"]
            raise Invalid, "#{type} needs a schema that describes an object" unless schema.is_a?(Hash) && schema["type"] == "object"

            check_schema!(schema, type)
          end

          declarations
        end

        private

          def entry!(entry)
            raise Invalid, "each authorization_details entry must be a JSON object" unless entry.is_a?(Hash)

            type = entry["type"]
            raise Invalid, "each authorization_details entry needs a type" unless type.is_a?(String) && type.match?(TYPE_FORMAT)

            entry.deep_stringify_keys
          end

          def check_schema!(schema, path)
            raise Invalid, "#{path} must be a JSON object" unless schema.is_a?(Hash)

            unknown = schema.keys - SCHEMA_KEYWORDS
            raise Invalid, "#{path} uses #{unknown.join(', ')}, which masks does not read" if unknown.any?
            raise Invalid, "#{path} needs a type of #{SCHEMA_TYPES.join(', ')}" unless SCHEMA_TYPES.include?(schema["type"])

            Array(schema["properties"]).each { |name, child| check_schema!(child, "#{path}.#{name}") }
            check_schema!(schema["items"], "#{path}[]") if schema["items"]
          end
      end

      def initialize(entries)
        @entries = entries
      end

      def each(&)
        entries.each(&)
      end

      def types
        entries.map { |entry| entry["type"] }.uniq
      end

      def as_json(*)
        entries
      end

      def canonical
        entries.map { |entry| normalized(entry) }.to_json
      end

      def covered_by?(granted)
        held = Array(granted&.entries || granted).map { |entry| normalized(entry) }

        entries.all? { |entry| held.include?(normalized(entry)) }
      end

      def check!(client, declared: self.class.declared)
        allowed = Array(client.authorization_details_types)

        entries.each do |entry|
          type = entry["type"]
          declaration = declared[type]

          raise Invalid, "#{type} is not a type of authorization detail this server accepts" if declaration.nil?
          raise Invalid, "#{client.name} has not registered #{type} in its authorization_details_types" unless allowed.include?(type)

          problem = Schema.new(declaration["schema"]).problem(entry.except("type"), type)
          raise Invalid, problem if problem
        end

        self
      end

      def described(declared: self.class.declared)
        entries.map do |entry|
          declaration = declared[entry["type"]] || {}

          {
            "type" => entry["type"],
            "label" => declaration["label"] || entry["type"],
            "fields" => entry.except("type").map { |name, value| [ name, Array(value).map(&:to_s).join(", ") ] }
          }
        end
      end

      private

        def normalized(entry)
          sort = ->(value) do
            case value
            when Hash then value.stringify_keys.sort.to_h.transform_values(&sort)
            when Array then value.map(&sort)
            else value
            end
          end

          sort.call(entry)
        end

      class Schema
        def initialize(schema)
          @schema = schema
        end

        def problem(value, path)
          check(@schema, value, path)
        end

        private

          def check(schema, value, path)
            return "#{path} must be one of #{schema['enum'].map(&:to_s).join(', ')}" if schema["enum"] && !schema["enum"].include?(value)

            case schema["type"]
            when "object" then object(schema, value, path)
            when "array" then array(schema, value, path)
            when "string" then string(schema, value, path)
            when "number", "integer" then number(schema, value, path)
            when "boolean" then "#{path} must be true or false" unless [ true, false ].include?(value)
            end
          end

          def object(schema, value, path)
            return "#{path} must be an object" unless value.is_a?(Hash)

            properties = schema["properties"] || {}

            missing = Array(schema["required"]) - value.keys
            return "#{path} needs #{missing.join(', ')}" if missing.any?

            extra = value.keys - properties.keys
            return "#{path} does not accept #{extra.join(', ')}" if extra.any? && schema["additionalProperties"] != true

            value.each do |name, child|
              next unless properties.key?(name)

              found = check(properties[name], child, "#{path}.#{name}")
              return found if found
            end

            nil
          end

          def array(schema, value, path)
            return "#{path} must be an array" unless value.is_a?(Array)
            return "#{path} holds more than #{schema['maxItems']} items" if schema["maxItems"] && value.size > schema["maxItems"]
            return nil unless schema["items"]

            value.each_with_index do |child, index|
              found = check(schema["items"], child, "#{path}[#{index}]")
              return found if found
            end

            nil
          end

          def string(schema, value, path)
            return "#{path} must be a string" unless value.is_a?(String)

            "#{path} is longer than #{schema['maxLength']} characters" if schema["maxLength"] && value.length > schema["maxLength"]
          end

          def number(schema, value, path)
            return "#{path} must be a number" unless value.is_a?(Numeric)
            return "#{path} must be a whole number" if schema["type"] == "integer" && !value.is_a?(Integer)
            return "#{path} must be at least #{schema['minimum']}" if schema["minimum"] && value < schema["minimum"]

            "#{path} must be at most #{schema['maximum']}" if schema["maximum"] && value > schema["maximum"]
          end
      end
    end
  end
end
