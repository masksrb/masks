# frozen_string_literal: true

module Masks::Mutations
  class Token < BaseMutation
    input_object_class Masks::Types::TokenInputType

    field :token, Masks::Types::TokenType, null: true
    field :errors, [String], null: true

    TYPES = {
      "access-token" => "Masks::AccessToken",
      "client-token" => "Masks::ClientToken",
    }

    def resolve(**args)
      token = nil

      if args[:id]
        token = Masks::Token.find_by(key: args[:id])
        token&.revoked(args[:revoked]) if args.key?(:revoked)
      elsif args[:type] && TYPES.fetch(args[:type], nil)
        client = Masks.client(args[:client])
        actor = Masks::Actor.find_by(key: args[:actor]) if args[:type] ==
          "access-token"
        token =
          Masks::Token.build(
            name: args[:name],
            type: TYPES.fetch(args[:type]),
            expiry: args[:expiry],
            deobfuscate: true,
            actor:,
            client:,
          )
      end

      token&.save

      { token:, errors: token&.errors&.full_messages&.uniq }
    end
  end
end
