# frozen_string_literal: true

module Masks::Mutations
  class Actor < BaseMutation
    input_object_class Masks::Types::ActorInputType

    field :actor, Masks::Types::ActorType, null: true
    field :errors, [String], null: true

    FIELDS = %i[name nickname scopes]

    def resolve(**args)
      actor =
        if args[:signup]
          Masks.actor(args[:identifier])
        else
          Masks.actor(key: args[:id], required: true)
        end

      if !args[:signup] && actor
        FIELDS.each do |field|
          actor.assign_attributes(field => args[field]) if args[field]
        end
      end

      actor.reset_backup_codes if args[:reset_backup_codes]

      unless args[:signup]
        if args[:password]
          actor.overwrite_password(args[:password])
        elsif args[:reset_password]
          actor.reset_password
        end
      end

      actor&.save

      { actor:, errors: actor&.errors&.full_messages&.uniq }
    end
  end
end
