module Masks
  module Server
    module Scim
      class GroupsController < ApplicationController
        include ScimEndpoint

        before_action :organization!, except: %i[index show]

        def index
          groups = Scim::Group.filter(provisioned_organization ? Scim::Group.all(provisioned_organization) : [], params[:filter])
          start = [ params[:startIndex].to_i, 1 ].max
          count = params[:count].present? ? params[:count].to_i.clamp(0, Scim::MAX_RESULTS) : Scim::MAX_RESULTS
          page = groups.drop(start - 1).first(count)

          scim({
            "schemas" => [ Scim::LIST ],
            "totalResults" => groups.size,
            "startIndex" => start,
            "itemsPerPage" => page.size,
            "Resources" => page.map { |group| represent(group) }
          })
        end

        def show
          scim(represent(found))
        end

        def create
          role = document["displayName"].to_s.strip.downcase

          raise Scim::Error.new(:bad_request, "a group is named by its displayName", scim_type: "invalidValue") if role.empty?
          raise Scim::Error.new(:conflict, "#{held.name} already has the role #{role}", scim_type: "uniqueness") if held.role?(role)

          unless role.match?(Organization::ROLE)
            raise Scim::Error.new(:bad_request, "a role is lowercase letters, digits, dashes, and underscores", scim_type: "invalidValue")
          end

          group = Scim::Group.new(held, role)

          Organization.transaction do
            roles!(held.roles + [ role ])
            replace!(group, group.member_ids(document["members"] || []))
          end

          response.headers["Location"] = "#{scim_base}/Groups/#{group.id}"
          scim(represent(group), status: :created)
        end

        def replace
          group = found
          group.changes([ { "op" => "replace", "value" => document.slice("displayName") } ]) if document.key?("displayName")

          Organization.transaction { replace!(group, group.member_ids(document["members"] || [])) }

          scim(represent(group))
        end

        def update
          group = found

          unless Array(document["schemas"]).include?(Scim::PATCH)
            raise Scim::Error.new(:bad_request, "a PATCH names #{Scim::PATCH}", scim_type: "invalidSyntax")
          end

          changes = group.changes(document["Operations"])

          Organization.transaction do
            replace!(group, changes[:replace]) if changes[:replace]
            replace!(group, []) if changes[:remove_all]
            changes[:add].each { |uuid| assign!(eligible!(uuid), group.role) }
            changes[:remove].each { |uuid| leave!(group, uuid) }
          end

          scim(represent(group))
        end

        def destroy
          group = found

          raise Scim::Error.new(:bad_request, "#{group.role} is built in to every organization", scim_type: "mutability") if group.built_in?

          if held.memberships.exists?(role: group.role)
            raise Scim::Error.new(:conflict, "people still hold #{group.role}; move them to another role first", scim_type: "mutability")
          end

          roles!(held.roles - [ group.role ])

          head :no_content
        end

        private

          def held
            provisioned_organization
          end

          def organization!
            return if held && !held.archived?

            raise Scim::Error.new(:forbidden, "groups are an organization's roles, so only a token for one live organization changes them")
          end

          def found
            (held && Scim::Group.find(held, params[:id])) || raise(Scim::Error.new(:not_found, "no group has that id"))
          end

          def represent(group)
            group.to_h(base: scim_base, members: !params[:excludedAttributes].to_s.split(",").map(&:strip).include?("members"))
          end

          def roles!(roles)
            held.roles = roles

            raise Scim::Error.new(:bad_request, held.errors.full_messages.to_sentence, scim_type: "invalidValue") unless held.save

            Event.record!(Event::ORGANIZATION_UPDATED, by: nil, organization: held, changed: [ "roles" ], via: "scim")
          end

          def replace!(group, uuids)
            wanted = uuids.uniq

            unless group.role == Organization::MEMBER
              group.memberships.each do |membership|
                next if wanted.include?(membership.actor.uuid) || !directory_owns?(membership.actor)

                assign!(membership, Organization::MEMBER)
              end
            end

            wanted.each { |uuid| assign!(eligible!(uuid), group.role) }
          end

          def leave!(group, uuid)
            return if group.role == Organization::MEMBER

            membership = group.memberships.detect { |holder| holder.actor.uuid == uuid }

            return if membership.nil?

            unless directory_owns?(membership.actor)
              raise Scim::Error.new(:forbidden, "#{held.name}'s directory did not create #{membership.actor.identifier}, " \
                                                "so it does not change their role", scim_type: "mutability")
            end

            assign!(membership, Organization::MEMBER)
          end

          def eligible!(uuid)
            actor = Actor.find_by(uuid: uuid) if uuid.match?(Subjects::UUID)
            membership = actor && held.memberships.accepted.find_by(actor: actor)

            return membership if membership && directory_owns?(actor)

            raise Scim::Error.new(:bad_request, "a group takes only people #{held.name}'s directory provisioned", scim_type: "invalidValue")
          end

          def assign!(membership, role)
            Members.assign!(membership, role: role, by: nil, via: "scim")
          rescue Members::Refused => e
            raise Scim::Error.new(:conflict, e.message, scim_type: "mutability")
          end
      end
    end
  end
end
