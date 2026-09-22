module ScopesHelper
  CONSEQUENTIAL = /(:write|:command|:exec|:delete|:admin)\z|\Aoffline_access\z|\Amasks:manage\z|\Amasks:delegate:./

  def consequential_scope?(scope)
    scope.to_s.match?(CONSEQUENTIAL)
  end

  def ranked_scopes(described)
    described.to_a.partition { |scope, _| consequential_scope?(scope) }
  end
end
