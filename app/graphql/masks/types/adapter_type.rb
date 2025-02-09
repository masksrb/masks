# frozen_string_literal: true

module Masks::Types
  class AdapterType < BaseObject
    field :key, String
    field :name, String
    field :type, String
    field :setup, Boolean
    field :primary, Boolean
    field :deleted, Boolean
    field :email_adapter, Boolean
    field :storage_adapter, Boolean
    field :phone_adapter, Boolean
    field :config, CamelizedJson

    def setup
      object.setup?
    end

    def primary
      (Masks.conf.storage_adapter == object.key && storage_adapter) ||
        (Masks.conf.email_adapter == object.key && email_adapter) ||
        (Masks.conf.phone_adapter == object.key && phone_adapter)
    end

    def email_adapter
      object.respond_to?(:to_mailer)
    end

    def storage_adapter
      object.respond_to?(:storage_service)
    end

    def phone_adapter
      object.respond_to?(:notify)
    end
  end
end
