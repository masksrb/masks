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
          field :delivered, Boolean, null: false
          field :url, String

          def resolve(organization:, role:, uuid: nil, email: nil)
            refuse!("name the person by uuid or by email, not both") if uuid && email
            refuse!("name the person by uuid or by email") if uuid.nil? && email.blank?

            held = live!(organization!(organization))
            actor = uuid ? actor!(uuid) : Actor.locate(email)&.then { |found| managed!(found) }

            Masks::Server::Members.add!(organization: held, role: role, by: viewer, actor: actor, email: email,
                                        journey: Masks::Server::Journey.manage(viewer))
          rescue Masks::Server::Members::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
