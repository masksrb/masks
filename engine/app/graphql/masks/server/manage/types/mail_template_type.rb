module Masks
  module Server
    module Manage
      module Types
        class MailTemplateType < BaseObject
          description "The tenant's own wording for one kind of email. masks still adds the button or code, how long it lasts, and the lines that keep a person safe."

          field :kind, ID, null: false,
                description: "Which email this changes, or `signature` for the closing lines every email ends with."
          field :subject, String, description: "The subject line. Blank keeps the one masks writes."
          field :message, String,
                description: "The opening text, in place of the one masks writes. A blank line starts a new paragraph. Blank keeps the one masks writes."
          field :placeholders, [ String ], null: false,
                description: "The names this kind fills in when written as `{{name}}`."
          field :updated_at, GraphQL::Types::ISO8601DateTime
        end
      end
    end
  end
end
