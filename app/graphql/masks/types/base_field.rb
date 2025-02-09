# frozen_string_literal: true

module Masks::Types
  class BaseField < GraphQL::Schema::Field
    argument_class BaseArgument

    # Override #initialize to take a new argument:
    def initialize(
      *args,
      serializer: false,
      managers_only: nil,
      **kwargs,
      &block
    )
      @managers_only = managers_only
      @serializer = serializer

      # Pass on the default args:
      super(*args, **kwargs, &block)
    end

    def visible?(context)
      return context[:serialize] if @serializer
      return Masks::MasksSchema.manager?(context) if @managers_only

      true
    end
  end
end
