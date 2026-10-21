module Masks
  module Server
    class HealthCheck < ApplicationRecord
      include TenantScoped

      OK = "ok".freeze
      WARNING = "warning".freeze
      FAILING = "failing".freeze
      STATUSES = [ OK, WARNING, FAILING ].freeze

      validates :name, presence: true, uniqueness: { scope: :tenant_id }
      validates :status, inclusion: { in: STATUSES }
      validates :summary, presence: true

      scope :failing, -> { where(status: FAILING) }
      scope :by_name, -> { order(:name) }

      def ok?
        status == OK
      end

      def failing?
        status == FAILING
      end
    end
  end
end
