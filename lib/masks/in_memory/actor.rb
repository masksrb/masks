module Masks
  module InMemory
    class Actor
      include ActiveModel::Attributes
      include ActiveModel::Validations
      include Masks::ActorSettings

      class << self
        def seed(**attrs)
          new(**attrs)
        end
      end
    end
  end
end
