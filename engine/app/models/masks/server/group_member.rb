module Masks
  module Server
    class GroupMember < ApplicationRecord
      include TenantScoped

      belongs_to :group
      belongs_to :actor
    end
  end
end
