module Masks
  module Server
    module Manage
      module Mutations
        class InviteActors < BaseMutation
          requires :support

          LIMIT = 200

          argument :emails, [ String ], description: "Up to 200 addresses. Blank lines and repeats are skipped."
          argument :groups, [ String ], required: false, description: "Keys of groups to put everyone invited in."

          field :outcomes, [ Types::InvitationOutcomeType ], null: false

          def resolve(emails:, groups: [])
            wanted = emails.map { |email| email.to_s.strip.downcase }.compact_blank.uniq
            refuse!("invite at most #{LIMIT} addresses at once") if wanted.size > LIMIT

            joining = groups.map { |key| Masks::Server::Group.find_by(key: key) || refuse!("no group called #{key}") }
            needs!(:security, "putting people in groups") if joining.any?

            { outcomes: wanted.map { |email| invite(email, joining) } }
          end

          private

            def invite(email, joining)
              return outcome(email, "invalid") unless email.match?(URI::MailTo::EMAIL_REGEXP)
              return outcome(email, "exists") if Actor.exists?(email: email)

              actor = Actor.create!(email: email, scopes: Scopes.join(Scopes::STANDARD))
              audit!(Masks::Server::Event::ACTOR_CREATED, actor: actor, scopes: actor.scope_list, invited: true)
              joining.each { |group| group.add!(actor) }

              sent = Invitations.open(actor: actor, journey: Masks::Server::Journey.manage(viewer))
              outcome(email, "invited", actor: actor, **sent.slice(:delivered, :url))
            rescue ActiveRecord::RecordInvalid
              outcome(email, "invalid")
            end

            def outcome(email, kind, actor: nil, delivered: false, url: nil)
              { email: email, outcome: kind, actor: actor, delivered: delivered, url: url }
            end
        end
      end
    end
  end
end
