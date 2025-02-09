module Masks
  module ScopesColumn
    extend ActiveSupport::Concern

    included { serialize :scopes, coder: JSON }

    def openid?
      scope?(Masks::Scopes::OPENID)
    end

    def masks_manager?
      scope?(Masks::Scopes::MANAGE)
    end

    def scopes_a
      return [] unless scopes

      map_scopes(scopes)
    end

    def scope?(scope)
      scopes_a.include?(scope.to_s)
    end

    def scopes?(*scopes)
      scopes.all? { |scope| scope?(scope) }
    end

    def assign_scopes(*list)
      self.scopes = [*scopes_a, *list].uniq.compact
    end

    def remove_scopes(*list)
      self.scopes = (scopes_a - map_scopes(list))
    end

    def assign_scopes=(list)
      assign_scopes(list)
    end

    def remove_scopes=(list)
      remove_scopes(list)
    end

    private

    def map_scopes(v)
      return [] unless v

      v
        .split("\n")
        .map { |line| line.split(" ") }
        .flatten
        .map { |line| line.split(",") }
        .flatten
        .compact
        .uniq
        .sort
    end
  end
end
