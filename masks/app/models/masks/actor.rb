# frozen_string_literal: true

module Masks
  class Actor < ApplicationRecord
    self.table_name = "masks_actors"

    include Seedable
  end
end
