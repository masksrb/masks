module Masks
  module Server
    class GroupMember < ApplicationRecord
      include TenantScoped

      belongs_to :group
      belongs_to :actor

      scope :manual, -> { where(sourced_by: nil) }
      scope :sourced, -> { where.not(sourced_by: nil) }

      def sourced?
        sourced_by.present?
      end
    end
  end
end
