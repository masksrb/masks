module Masks
  module Server
    module MailPreviews
      Adapter = Data.define(:from) do
        def delivery_method = [ :test ]
      end

      Preview = Data.define(:key, :name, :subject, :from, :to, :html, :text)

      class << self
        def all(tenant, origin)
          Current.set(previewing: true) do
            entries(tenant, origin.presence || tenant.public_origin.to_s).map do |key, name, delivery|
              render(key, name, delivery.message)
            end
          end
        end

        private

          def entries(tenant, origin)
            named = tenant.name
            person = Actor.new(uuid: "preview", nickname: "sam", email: "sam@example.com", name: "Sam Rivera")
            manager = Actor.new(uuid: "manager", nickname: "ada", email: "ada@example.com", name: "Ada Park")
            due = IdleAccounts::WARNING.from_now
            changed = Event.new(action: Event::PASSWORD_CHANGED, actor: person, created_at: Time.current,
                                ip_address: "203.0.113.7")

            [
              [ "invitation", "Invitation",
                ActorMailer.invitation(person, "#{origin}/invite/preview", tenant_name: named, invited_by: manager) ],
              [ "password_reset", "Password reset",
                ActorMailer.password_reset(person, "#{origin}/reset/preview", tenant_name: named) ],
              [ "email_verification", "Email confirmation",
                ActorMailer.email_verification(person, "#{origin}/verify/preview", tenant_name: named) ],
              [ "confirmation_code", "Confirmation code",
                ActorMailer.confirmation_code(person.email, "482913", tenant_name: named) ],
              [ "notification", "Security notice",
                ActorMailer.notification(person, changed, tenant_name: named, origin: origin) ],
              [ "approval_requested", "Approval requested",
                ActorMailer.approval_requested(manager, person, tenant_name: named, origin: origin) ],
              [ "approved", "Account approved",
                ActorMailer.approved(person, tenant_name: named, origin: origin) ],
              [ "idle_suspend", "Idle, before suspension",
                ActorMailer.idle(person, tenant_name: named, due: due, notice: IdleAccounts::SUSPEND, origin: origin) ],
              [ "idle_delete", "Idle, before deletion",
                ActorMailer.idle(person, tenant_name: named, due: due, notice: IdleAccounts::DELETE, origin: origin) ],
              [ "idle_delete_suspended", "Idle and suspended, before deletion",
                ActorMailer.idle(person, tenant_name: named, due: due, notice: IdleAccounts::DELETE_SUSPENDED, origin: origin) ],
              [ "adapter_trial", "Mail adapter test",
                AdapterMailer.trial(manager.email, adapter: Adapter.new(from: ApplicationMailer.from)) ]
            ]
          end

          def render(key, name, message)
            Preview.new(
              key: key,
              name: name,
              subject: message.subject.to_s,
              from: Array(message.from).join(", "),
              to: Array(message.to).join(", "),
              html: part(message, "text/html"),
              text: part(message, "text/plain")
            )
          end

          def part(message, type)
            found = message.multipart? ? message.parts.find { |each| each.mime_type == type } : message
            found&.mime_type == type ? found.decoded : nil
          end
      end
    end
  end
end
