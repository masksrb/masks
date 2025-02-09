# frozen_string_literal: true

module Masks::Mutations
  class OtpSecret < BaseMutation
    input_object_class Masks::Types::OtpSecretInputType

    field :otp_secret, Masks::Types::OtpSecretType, null: true
    field :otp_secrets, [Masks::Types::OtpSecretType], null: true
    field :errors, [String], null: true

    def resolve(**args)
      actor = Masks::Actor.find_by(key: args[:actor_id])

      return { errors: ["unknown actor"] } unless actor

      otp_secrets = actor.otp_secrets
      otp_secret =
        case args[:action]
        when "delete"
          otp_secrets.find_by(public_id: args[:id])
        end

      if args[:action] == "delete"
        otp_secret&.destroy if otp_secret&.valid?
      end

      { otp_secret:, otp_secrets:, errors: otp_secret&.errors&.full_messages }
    end
  end
end
