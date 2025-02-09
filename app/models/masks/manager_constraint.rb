module Masks
  class ManagerConstraint
    def matches?(request)
      Masks::Entries::Internal.manager?(request.env["masks.session"])
    end
  end
end
