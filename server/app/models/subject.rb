class Subject < ApplicationRecord
  include TenantScoped

  belongs_to :actor

  validates :sector, presence: true
  validates :sub, presence: true, uniqueness: { scope: :tenant_id }

  normalizes :sector, with: ->(value) { value.to_s.strip.downcase.presence }
end
