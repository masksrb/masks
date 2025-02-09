# frozen_string_literal: true

module Masks
  class ClientProvider < ApplicationRecord
    self.table_name = "masks_client_providers"

    belongs_to :client, class_name: "Masks::Client"
    belongs_to :provider, class_name: "Masks::Provider"

    validates :client_id, uniqueness: { scope: :provider_id }
  end
end
