module Masks
  module Server
    module Manage
      module Mutations
        class InviteActors < BaseMutation
          requires :support

          LIMIT = 200

          argument :emails, [ String ], description: "Up to #{LIMIT} addresses. Blank lines and repeats are skipped."
          argument :groups, [ String ], required: false, description: "Keys of groups to put everyone invited in."

          field :outcomes, [ Types::InvitationOutcomeType ], null: false

          def resolve(emails:, groups: [])
            wanted = emails.filter_map { |email| Actor.normalize_value_for(:email, email) }.uniq
            refuse!("invite at most #{LIMIT} addresses at once") if wanted.size > LIMIT

            joining = groups.map { |key| group!(key) }
            needs!(:security, "putting people in groups") if joining.any?

            { outcomes: wanted.map { |email| invite(email, joining) } }
          end

          private

            def invite(email, joining)
              actor = Actor.new(email: email, scopes: Scopes.join(Scopes::STANDARD))

              unless actor.save
                return outcome(email, actor.errors.of_kind?(:email, :taken) ? "exists" : "invalid")
              end

              joining.each { |group| group.add!(actor, by: viewer) }

              outcome(email, "invited", actor: actor, **invited!(actor))
            end

            def outcome(email, kind, actor: nil, delivered: false, url: nil)
              { email: email, outcome: kind, actor: actor, delivered: delivered, url: url }
            end
        end
      end
    end
  end
end
