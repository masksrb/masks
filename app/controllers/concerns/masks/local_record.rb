module Masks
  module LocalRecord
    extend ActiveSupport::Concern

    included do
      setting :local, :boolean, public: true

      validates :local, absence: true
    end
  end
end
