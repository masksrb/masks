module Masks
  module Server
    module MailPreviews
      Adapter = Data.define(:from) do
        def delivery_method = [ :test ]
      end

      Preview = Data.define(:key, :name, :journey, :heading, :subject, :from, :to, :html, :text)

      class << self
        def all(client: nil)
          Current.set(previewing: true) do
            entries(client).map { |key, name, journey, delivery| render(key, name, journey, delivery.message) }
          end
        end

        private

          def entries(client)
            person = Actor.new(uuid: "preview", nickname: "sam", email: "sam@example.com", name: "Sam Rivera")
            manager = Actor.new(uuid: "manager", nickname: "ada", email: "ada@example.com", name: "Ada Park")
            signing_in = Journey.new(kind: Journey::SIGN_IN, via: Journey::AUTHORIZATION, client: client)
            managing = Journey.manage(manager)
            system = Journey.system
            origin = signing_in.origin
            due = IdleAccounts::WARNING.from_now
            changed = Event.new(action: Event::PASSWORD_CHANGED, actor: person, created_at: Time.current,
                                ip_address: "203.0.113.7")
            acme = Organization.new(key: "acme", name: "Acme", roles: [ "billing" ])
            joining = Membership.new(organization: acme, actor: person, role: "billing", invited_by: manager,
                                     invited_as: person.email, pending: true)
            promoted = Event.new(action: Event::MEMBERSHIP_ROLE_CHANGED, actor: person, by: manager, organization: acme,
                                 created_at: Time.current, details: { "was" => "member", "now" => "owner" })

            [
              [ "confirmation_code", "Confirmation code", signing_in,
                ActorMailer.confirmation_code(person.email, "482913", journey: signing_in) ],
              [ "email_verification", "Email confirmation", signing_in,
                ActorMailer.email_verification(person, "#{origin}/verify/preview", journey: signing_in) ],
              [ "password_reset", "Password reset", signing_in,
                ActorMailer.password_reset(person, "#{origin}/reset/preview", journey: signing_in) ],
              [ "approval_requested", "Approval requested", signing_in,
                ActorMailer.approval_requested(manager, person, journey: signing_in) ],
              [ "recovery_requested", "Help signing in requested", signing_in,
                ActorMailer.recovery_requested(manager, person, journey: signing_in) ],
              [ "invitation", "Invitation", managing,
                ActorMailer.invitation(person, "#{origin}/invite/preview", journey: managing) ],
              [ "invitation_organization", "Invitation to an organization", managing,
                ActorMailer.invitation(person, "#{origin}/invite/preview", journey: managing, membership: joining) ],
              [ "organization_invitation", "Added to an organization", managing,
                ActorMailer.organization_invitation(joining, journey: managing) ],
              [ "approved", "Account approved", managing,
                ActorMailer.approved(person, journey: managing) ],
              [ "notification", "Security notice", system,
                ActorMailer.notification(person, changed, journey: system) ],
              [ "notification_organization", "Organization role changed", system,
                ActorMailer.notification(person, promoted, journey: system) ],
              [ "idle_suspend", "Idle, before suspension", system,
                ActorMailer.idle(person, due: due, notice: IdleAccounts::SUSPEND, journey: system) ],
              [ "idle_delete", "Idle, before deletion", system,
                ActorMailer.idle(person, due: due, notice: IdleAccounts::DELETE, journey: system) ],
              [ "idle_delete_suspended", "Idle and suspended, before deletion", system,
                ActorMailer.idle(person, due: due, notice: IdleAccounts::DELETE_SUSPENDED, journey: system) ],
              [ "adapter_trial", "Mail adapter test", managing,
                AdapterMailer.trial(manager.email, adapter: Adapter.new(from: ApplicationMailer.from), journey: managing) ]
            ]
          end

          def render(key, name, journey, message)
            Preview.new(
              key: key,
              name: name,
              journey: journey.kind,
              heading: journey.heading.to_s,
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
