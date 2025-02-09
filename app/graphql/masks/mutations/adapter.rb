# frozen_string_literal: true

module Masks::Mutations
  class Adapter < BaseMutation
    input_object_class Masks::Types::AdapterInputType

    field :adapter, Masks::Types::AdapterType, null: true
    field :errors, [String], null: true

    def resolve(**args)
      add = false
      key =
        if args[:key]
          args[:key]
        elsif args[:name]
          add = true
          args[:name].parameterize
        end

      mode = Masks.conf
      adapter = nil

      if key && ((mode.adapters[key] && !add) || (!mode.adapters[key] && add))
        if args[:deleted] && !add
          adapter = Masks.conf.adapters[key]
          adapter.deleted = true

          Masks.conf.modify_adapter(key:, deleted: true).save!
        else
          updates = args.except(:config).deep_merge(key:, **args[:config] || {})

          Masks.conf.modify_adapter(**updates).save!

          adapter = Masks.conf.adapters[key]
        end
      end

      { adapter: }
    end
  end
end
