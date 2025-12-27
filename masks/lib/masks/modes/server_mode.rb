# frozen_string_literal: true

module Masks
  module ServerMode
    extend ActiveSupport::Concern

    included do
      include Masks::Mode

      def devices
        Masks::Device
      end

      def sessions
        Masks::Sessions::Server
      end
    end
  end
end
