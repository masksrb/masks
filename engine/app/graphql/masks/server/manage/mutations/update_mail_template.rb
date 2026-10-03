module Masks
  module Server
    module Manage
      module Mutations
        class UpdateMailTemplate < BaseMutation
          requires :owner

          description "Sets the tenant's wording for one kind of email. Leaving both the subject and the message blank goes back to the wording masks writes."

          argument :kind, ID
          argument :subject, String, required: false
          argument :message, String, required: false

          field :mail_template, Types::MailTemplateType, null: false

          def resolve(kind:, subject: nil, message: nil)
            refuse!("no email is called #{kind}") unless MailTemplate::KINDS.key?(kind)

            template = MailTemplate.for(kind) || MailTemplate.new(kind: kind)
            template.assign_attributes(subject: subject, message: message)

            if template.subject.nil? && template.message.nil?
              template.destroy! if template.persisted?
              template = MailTemplate.new(kind: kind)
            else
              save!(template)
            end

            audit!(Masks::Server::Event::MAIL_TEMPLATE_UPDATED, kind: kind, custom: template.persisted?)

            { mail_template: template }
          end
        end
      end
    end
  end
end
