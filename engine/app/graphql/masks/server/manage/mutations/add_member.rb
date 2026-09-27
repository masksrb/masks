module Masks
  module Server
    module Manage
      module Mutations
        class AddMember < OrganizationMutation
          requires :support

          description "Adds a person to an organization. Name an existing account by uuid, or an email " \
                      "address, which invites a new account when none holds it."

          argument :organization, ID
          argument :role, String
          argument :uuid, ID, required: false
          argument :email, String, required: false

          field :membership, Types::MembershipType, null: false
          field :invited, Boolean, null: false
          field :delivered, Boolean, null: false
          field :url, String

          def resolve(organization:, role:, uuid: nil, email: nil)
            refuse!("name the person by uuid or by email, not both") if uuid && email
            refuse!("name the person by uuid or by email") if uuid.nil? && email.blank?

            held = live!(organization!(organization))
            actor = uuid ? actor!(uuid) : managed!(Actor.locate(email) || invitee(email))

            refuse!("#{actor.identifier} is already a member of #{held.name}") if held.memberships.exists?(actor: actor)

            membership = save!(held.memberships.new(actor: actor, role: role, invited_by: viewer))

            audit!(Masks::Server::Event::MEMBERSHIP_ADDED, actor: actor, organization: held.key, role: role)

            sent = actor.activated? ? { delivered: false, url: nil } : invite(actor)

            { membership: membership, invited: !actor.activated? }.merge(sent)
          end

          private

            def invitee(email)
              actor = save!(Actor.new(email: email, scopes: Scopes.join(Scopes::STANDARD)))

              audit!(Masks::Server::Event::ACTOR_CREATED, actor: actor, scopes: actor.scope_list, invited: true)

              actor
            end

            def invite(actor)
              return { delivered: false, url: nil } if actor.email.blank?

              Invitations.open(actor: actor, journey: Masks::Server::Journey.manage(viewer)).slice(:delivered, :url)
            rescue Masks::Server::Invitation::Refused
              { delivered: false, url: nil }
            end
        end
      end
    end
  end
end
