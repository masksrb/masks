# frozen_string_literal: true

module Masks::Types
  class EmailType < BaseObject
    field :address, String
    field :group, String
    field :actor, ActorType, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: true
    field :verified_at, GraphQL::Types::ISO8601DateTime, null: true
    field :login_link, Boolean
    field :verify_link, Boolean

    bool :deletable

    def verify_link
      if context[:device]
        object
          .login_links
          .active
          .for_verification
          .where(device: context[:device])
          .any?
      else
        object.login_links.active.for_verification.any?
      end
    end

    def login_link
      return false unless object.for_login?

      if context[:auth]&.device
        object
          .login_links
          .active
          .for_login
          .where(device: context[:auth].device)
          .any?
      else
        object.login_links.active.for_login.any?
      end
    end

    def log_in
      object.for_login?
    end
  end
end
