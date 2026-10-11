module Masks
  module Server
    module Ldap
      module Filter
        class Invalid < StandardError; end

        AND = 0xa0
        OR = 0xa1
        NOT = 0xa2
        EQUALITY = 0xa3
        SUBSTRINGS = 0xa4
        GREATER_OR_EQUAL = 0xa5
        LESS_OR_EQUAL = 0xa6
        PRESENT = 0x87
        APPROXIMATE = 0xa8
        EXTENSIBLE = 0xa9

        INITIAL = 0x80
        ANY = 0x81
        FINAL = 0x82

        DISTINGUISHED = %w[member memberof].freeze

        All = Data.define(:filters) do
          def match(entry)
            results = filters.map { |filter| filter.match(entry) }
            return false if results.include?(false)

            results.include?(nil) ? nil : true
          end
        end

        Any = Data.define(:filters) do
          def match(entry)
            results = filters.map { |filter| filter.match(entry) }
            return true if results.include?(true)

            results.include?(nil) ? nil : false
          end
        end

        Negated = Data.define(:filter) do
          def match(entry)
            result = filter.match(entry)

            result.nil? ? nil : !result
          end
        end

        Equal = Data.define(:attribute, :value) do
          def match(entry)
            wanted = Filter.comparable(attribute, value)

            entry.values(attribute).any? { |held| Filter.comparable(attribute, held) == wanted }
          end
        end

        Present = Data.define(:attribute) do
          def match(entry)
            entry.values(attribute).any?
          end
        end

        Substrings = Data.define(:attribute, :initial, :middle, :final) do
          def match(entry)
            entry.values(attribute).any? { |held| fits?(held.to_s.downcase) }
          end

          private

            def fits?(held)
              position = 0

              if initial
                return false unless held.start_with?(initial.downcase)

                position = initial.length
              end

              middle.each do |part|
                found = held.index(part.downcase, position)
                return false if found.nil?

                position = found + part.length
              end

              return true unless final

              held.length - final.length >= position && held.end_with?(final.downcase)
            end
        end

        Ordered = Data.define(:attribute, :value, :direction) do
          def match(entry)
            wanted = value.downcase

            entry.values(attribute).any? do |held|
              compared = held.to_s.downcase <=> wanted
              direction == :greater ? compared >= 0 : compared <= 0
            end
          end
        end

        Unknown = Data.define do
          def match(_entry)
            nil
          end
        end

        module_function

        def from(element, depth = 0)
          raise Invalid, "a filter nests deeper than #{Ber::DEEPEST}" if depth > Ber::DEEPEST

          case element.tag
          when AND then All.new(filters: element.children.map { |part| from(part, depth + 1) })
          when OR then Any.new(filters: element.children.map { |part| from(part, depth + 1) })
          when NOT then Negated.new(filter: from(element.child(0), depth + 1))
          when EQUALITY, APPROXIMATE then Equal.new(**assertion(element))
          when GREATER_OR_EQUAL then Ordered.new(**assertion(element), direction: :greater)
          when LESS_OR_EQUAL then Ordered.new(**assertion(element), direction: :less)
          when PRESENT then Present.new(attribute: attribute(element.string))
          when SUBSTRINGS then substrings(element)
          when EXTENSIBLE then Unknown.new
          else raise Invalid, "#{format('%#04x', element.tag)} is not a filter"
          end
        rescue Ber::Error => e
          raise Invalid, e.message
        end

        def parse(text)
          filter, rest = parse_at(text.to_s.strip, 0)
          raise Invalid, "#{text} has more after the filter" unless rest == text.to_s.strip.length

          filter
        end

        def pinned(filter, attribute)
          case filter
          when Equal then filter.value if filter.attribute == attribute
          when All then filter.filters.lazy.filter_map { |part| pinned(part, attribute) }.first
          end
        end

        def comparable(attribute, value)
          return value.to_s.downcase unless DISTINGUISHED.include?(attribute.to_s.downcase)

          Dn.parse(value).normal
        rescue Dn::Invalid
          value.to_s.downcase
        end

        def attribute(description)
          description.to_s.split(";").first.to_s.downcase
        end

        def assertion(element)
          { attribute: attribute(element.child(0).string), value: utf8(element.child(1).string) }
        end

        def substrings(element)
          initial = nil
          final = nil
          middle = []

          element.child(1).children.each do |part|
            case part.tag
            when INITIAL then initial = utf8(part.string)
            when ANY then middle << utf8(part.string)
            when FINAL then final = utf8(part.string)
            end
          end

          Substrings.new(attribute: attribute(element.child(0).string), initial: initial, middle: middle, final: final)
        end

        def utf8(bytes)
          bytes.dup.force_encoding(Encoding::UTF_8).scrub
        end

        def parse_at(text, position)
          raise Invalid, "a filter starts with (" unless text[position] == "("

          position += 1

          case text[position]
          when "&", "|"
            kind = text[position]
            filters = []
            position += 1

            while text[position] == "("
              filter, position = parse_at(text, position)
              filters << filter
            end

            [ kind == "&" ? All.new(filters: filters) : Any.new(filters: filters), closing(text, position) ]
          when "!"
            filter, position = parse_at(text, position + 1)

            [ Negated.new(filter: filter), closing(text, position) ]
          else
            finish = text.index(")", position) || raise(Invalid, "a filter never closes")
            [ simple(text[position...finish]), finish + 1 ]
          end
        end

        def closing(text, position)
          raise Invalid, "a filter never closes" unless text[position] == ")"

          position + 1
        end

        def simple(item)
          type, operator, value = item.match(/\A([^=<>~]+)(=|>=|<=|~=)(.*)\z/m)&.captures
          raise Invalid, "#{item} is not a filter" if type.nil?

          type = attribute(type.strip)

          case operator
          when ">=" then Ordered.new(attribute: type, value: unescaped(value), direction: :greater)
          when "<=" then Ordered.new(attribute: type, value: unescaped(value), direction: :less)
          else
            return Present.new(attribute: type) if value == "*"
            return Equal.new(attribute: type, value: unescaped(value)) unless value.include?("*")

            parts = value.split("*", -1).map { |part| unescaped(part) }
            Substrings.new(attribute: type, initial: parts.first.presence, middle: parts[1..-2].compact_blank,
                           final: parts.last.presence)
          end
        end

        def unescaped(value)
          value.b.gsub(/\\(\h\h)/n) { ::Regexp.last_match(1).to_i(16).chr }.force_encoding(Encoding::UTF_8).scrub
        end
      end
    end
  end
end
