# frozen_string_literal: true

module Masks::Types
  class MutationType < BaseObject
    # Admin features
    field :email, mutation: Masks::Mutations::Email, managers_only: true
    field :phone, mutation: Masks::Mutations::Phone, managers_only: true
    field :otp_secret,
          mutation: Masks::Mutations::OtpSecret,
          managers_only: true
    field :hardware_key,
          mutation: Masks::Mutations::HardwareKey,
          managers_only: true
    field :provider, mutation: Masks::Mutations::Provider, managers_only: true
    field :actor, mutation: Masks::Mutations::Actor, managers_only: true
    field :client, mutation: Masks::Mutations::Client, managers_only: true
    field :device, mutation: Masks::Mutations::Device, managers_only: true
    field :token, mutation: Masks::Mutations::Token, managers_only: true
    field :conf, mutation: Masks::Mutations::Conf, managers_only: true
    field :deletion, mutation: Masks::Mutations::Deletion, managers_only: true
    field :adapter, mutation: Masks::Mutations::Adapter, managers_only: true
  end
end
