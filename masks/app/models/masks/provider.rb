# frozen_string_literal: true

module Masks
  class Provider < ApplicationRecord
    self.table_name = "masks_providers"

    include Seedable
  end
end
