module Masks
  module Server
    module Manage
      module Types
        class MailPreviewType < BaseObject
          field :key, ID, null: false
          field :name, String, null: false
          field :journey, String, null: false
          field :heading, String, null: false
          field :subject, String, null: false
          field :from, String, null: false
          field :to, String, null: false
          field :html, String
          field :text, String
        end
      end
    end
  end
end
