module Masks
  module Server
    module ScopesHelper
      CONSEQUENTIAL = /(:write|:command|:exec|:delete|:admin)\z|\Aoffline_access\z|\Amasks:manage(:[a-z]+)?\z|\Amasks:delegate:./

      SEEN = [
        Scopes::OPENID, Scopes::PROFILE, Scopes::EMAIL,
        Scopes::IDENTITIES, Scopes::ORGANIZATION, Scopes::GROUPS
      ].freeze

      def consequential_scope?(scope)
        scope.to_s.match?(CONSEQUENTIAL)
      end

      def heeded_scope?(scope)
        scope == Scopes::DELEGATE || consequential_scope?(scope)
      end

      def ranked_scopes(described)
        described.to_a.partition { |scope, _| consequential_scope?(scope) }
      end

      def plain_scopes(described, areas: [])
        held = { sees: [], heeds: [], also: [] }

        described.to_a.each do |scope, description|
          next if areas.include?(scope)

          group =
            if heeded_scope?(scope) then :heeds
            elsif SEEN.include?(scope) then :sees
            else :also
            end

          held[group] << [ scope, description ]
        end

        held[:sees].sort_by! { |scope, _| SEEN.index(scope) }
        held
      end
    end
  end
end
