module Masks
  module Server
    module Scim
      class GroupsController < ApplicationController
        include ScimEndpoint

        before_action :organization!, except: %i[index show]

        def index
          groups = Scim::Group.filter(held ? Scim::Group.all(held, holders: (held.memberships.accepted if members?)) : [], params[:filter])
          start, count = scim_page

          scim(listed(groups.drop(start - 1).first(count).map { |group| represent(group) }, total: groups.size, start: start))
        end

        def show
          scim(represent(found))
        end

        def create
          role = document["displayName"].to_s.strip.downcase

          raise Scim::Error.new(:bad_request, "a group is named by its displayName", scim_type: "invalidValue") if role.empty?
          raise Scim::Error.new(:conflict, "#{held.name} already has the role #{role}", scim_type: "uniqueness") if held.role?(role)

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
          group.rename!(document["displayName"]) if document.key?("displayName")

          Organization.transaction { replace!(group, group.member_ids(document["members"] || [])) }

          scim(represent(group))
        end

        def update
          group = found
          patch_document!

          changes = group.changes(document["Operations"])

          Organization.transaction do
            replace!(group, changes[:replace]) if changes[:replace]
            eligible!(changes[:add]).each { |membership| assign!(membership, group.role) }
            changes[:remove].each { |uuid| leave!(group, uuid) }
          end

          scim(represent(group))
        end

        def destroy
          group = found

          raise Scim::Error.new(:bad_request, "#{group.role} is built in to every organization", scim_type: "mutability") if group.built_in?

          roles!(held.roles - [ group.role ])

          head :no_content
        end

        private

          def held
            directory.organization
          end

          def organization!
            return if held && !held.archived?

            raise Scim::Error.new(:forbidden, "groups are an organization's roles, so only a token for one live organization changes them")
          end

          def found
            (held && Scim::Group.find(held, params[:id])) || raise(Scim::Error.new(:not_found, "no group has that id"))
          end

          def members?
            !params[:excludedAttributes].to_s.split(",").map(&:strip).include?("members")
          end

          def represent(group)
            group.to_h(base: scim_base, members: members?)
          end

          def roles!(roles)
            held.roles = roles

            unless held.save
              raise Scim::Error.new(:conflict, held.errors.full_messages.to_sentence, scim_type: "mutability") if held.errors.of_kind?(:base, :held)
              raise Scim::Error.new(:bad_request, held.errors.full_messages.to_sentence, scim_type: "invalidValue")
            end

            Event.record!(Event::ORGANIZATION_UPDATED, by: nil, organization: held, changed: [ "roles" ], via: "scim")
          end

          def replace!(group, uuids)
            wanted = uuids.to_set

            unless group.role == Organization::MEMBER
              holders = group.memberships.reject { |membership| wanted.include?(membership.actor.uuid) }
              owned = directory.owned(holders.map(&:actor_id))

              holders.each { |membership| assign!(membership, Organization::MEMBER) if owned.include?(membership.actor_id) }
            end

            eligible!(wanted).each { |membership| assign!(membership, group.role) }
          end

          def leave!(group, uuid)
            return if group.role == Organization::MEMBER

            membership = group.memberships.find_by(actors: { uuid: uuid })

            return if membership.nil?

            unless directory.owned([ membership.actor_id ]).any?
              raise Scim::Error.new(:forbidden, "#{held.name}'s directory did not create #{membership.actor.identifier}, " \
                                                "so it does not change their role", scim_type: "mutability")
            end

            assign!(membership, Organization::MEMBER)
          end

          def eligible!(uuids)
            uuids = uuids.to_a.uniq
            actors = Actor.where(uuid: uuids.grep(Subjects::UUID)).index_by(&:uuid)
            memberships = held.memberships.accepted.where(actor_id: actors.values.map(&:id)).index_by(&:actor_id)
            owned = directory.owned(memberships.keys)

            uuids.map do |uuid|
              membership = actors[uuid] && memberships[actors[uuid].id]

              next membership if membership && owned.include?(membership.actor_id)

              raise Scim::Error.new(:bad_request, "a group takes only people #{held.name}'s directory provisioned", scim_type: "invalidValue")
            end
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
