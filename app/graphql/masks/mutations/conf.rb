# frozen_string_literal: true

module Masks::Mutations
  class Conf < BaseMutation
    input_object_class Masks::Types::ServerInputType

    field :server, Masks::Types::ServerType, null: true
    field :errors, [String], null: true

    def resolve(**args)
      conf = Masks.conf

      if args.any? && conf.writable?
        defaults = args.delete(:client_defaults)
        conf.client_defaults = defaults if defaults
        args.each { |k, v| conf.setting!(k, v) }
        conf.save!
      end

      { server: conf } if Masks.mode.server?
    end
  end
end
