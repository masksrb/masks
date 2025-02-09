# frozen_string_literal: true

module Masks::Mutations
  class Client < BaseMutation
    input_object_class Masks::Types::ClientInputType

    field :client, Masks::Types::ClientType, null: false
    field :errors, [String], null: true

    def resolve(**args)
      client =
        (
          if args[:id]
            Masks::Client.create_with(
              client_type: args[:type],
            ).find_or_initialize_by(key: args[:id])
          else
            Masks::Client.new(client_type: args[:type])
          end
        )

      client.name = args[:name] if args[:name]
      client.secret = args[:secret] if args[:secret]
      client.internal = args[:internal] if args.key?(:internal)
      client.pkce = args[:pkce] if args.key?(:pkce)
      client.redirect_uris = args[:redirect_uris] if args[:redirect_uris]
      client.pairwise_salt = args[:pairwise_salt] if args[:pairwise_salt]
      client.merge_settings(args)
      client.save

      { client:, errors: client.errors.full_messages }
    end
  end
end
