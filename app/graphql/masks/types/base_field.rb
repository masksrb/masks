# frozen_string_literal: true

module Masks::Types
  class BaseField < GraphQL::Schema::Field
    argument_class BaseArgument

    # Override #initialize to take a new argument:
    def initialize(*args, managers_only: nil, **kwargs, &block)
      @managers_only = managers_only

      # Pass on the default args:
      super(*args, **kwargs, &block)
    end

    def visible?(context)
      @managers_only ? context[:manager] : true
    end
  end
end
