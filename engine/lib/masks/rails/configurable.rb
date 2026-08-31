module Masks
  module Rails
    module Configurable
      extend ActiveSupport::Concern

      def masks_config
        Masks::Rails.config
      end
    end
  end
end
