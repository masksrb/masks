module Masks
  module Server
    module Ldap
      class Entry
        attr_reader :dn, :attributes

        def initialize(dn, attributes)
          @dn = dn
          @attributes = attributes.transform_values { |values| Array(values).compact.map(&:to_s).reject(&:empty?) }
                                  .reject { |_name, values| values.empty? }
        end

        def values(name)
          wanted = name.to_s.downcase
          found = attributes.find { |held, _values| held.downcase == wanted }

          found ? found.last : []
        end

        def selected(requested)
          wanted = requested.map(&:downcase)
          return [] if wanted == [ "1.1" ]
          return attributes.to_a if wanted.empty? || wanted.include?("*") || wanted.include?("+")

          attributes.select { |name, _values| wanted.include?(name.downcase) }.to_a
        end
      end
    end
  end
end
