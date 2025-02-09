module Masks
  module InMemory
    class Client
      include ActiveModel::Attributes
      include ActiveModel::Validations
      include Masks::ClientSettings

      attr_accessor :settings

      class << self
        def seed(**attrs)
          new(**attrs)
        end
      end
    end
  end
end
