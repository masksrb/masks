# frozen_string_literal: true

module Masks::Mutations
  class Provider < BaseMutation
    input_object_class Masks::Types::ProviderInputType

    field :provider, Masks::Types::ProviderType, null: true
    field :errors, [String], null: true

    def resolve(**args)
      provider =
        if args[:id]
          record = Masks.provider(args[:id])

          args
            .except(:id, :settings, :enabled)
            .each { |k, v| record.send("#{k}=", v) }

          args[:settings]&.each { |k, v| record.send("#{k}=", v) }

          record
        elsif args[:type]
          attrs = args.slice(:name, :settings, :common)

          Masks::Provider.seed(
            key: nil,
            type: args[:type],
            disabled_at: Time.current,
            **attrs,
          )
        end

      if args.key?(:enabled)
        args[:enabled] ? provider&.enable : provider&.disable
      end

      provider&.save

      { provider:, errors: provider&.errors&.full_messages }
    end
  end
end
