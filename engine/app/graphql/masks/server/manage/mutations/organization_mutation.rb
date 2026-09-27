module Masks
  module Server
    module Manage
      module Mutations
        class OrganizationMutation < BaseMutation
          private

            def organization!(key)
              Masks::Server::Organization.find_by(key: key) || refuse!("no organization keyed #{key}")
            end

            def member!(organization, actor)
              organization.memberships.find_by(actor: actor) ||
                refuse!("#{actor.identifier} is not a member of #{organization.name}")
            end

            def live!(organization)
              refuse!("#{organization.name} is archived; restore it first") if organization.archived?

              organization
            end
        end
      end
    end
  end
end
