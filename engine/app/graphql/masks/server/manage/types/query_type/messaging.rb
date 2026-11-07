module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Messaging
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            included do
              field :senders, [ SenderType ], null: false do
                argument :kind, String, required: false
                argument :archived, Boolean, required: false
              end

              field :sender_services, [ SenderServiceType ], null: false

              field :mail_previews, [ MailPreviewType ], null: false do
                argument :client, ID, required: false
              end

              field :mail_templates, [ MailTemplateType ], null: false,
                    description: "One entry for each email the tenant can reword, and the signature."
            end

            def senders(kind: nil, archived: false)
              scope = Masks::Server::Sender.listed(archived)
              scope = scope.where(kind: kind) if kind

              scope.order(:kind, primary: :desc, name: :asc)
            end

            def sender_services
              Masks::Server::Sender.services.map do |klass|
                { service: klass.service, kind: klass.kind, label: klass.label, fields: klass.fields.map(&:to_h) }
              end
            end

            def mail_previews(client: nil)
              MailPreviews.all(client: client && Client.find_by(client_id: client))
            end

            def mail_templates
              MailTemplate.each_kind
            end
          end
        end
      end
    end
  end
end
