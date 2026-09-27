module Masks
  module Server
    module Scim
      class Directory
        ID = "directory_id".freeze

        def self.for(organization)
          organization ? OrganizationDirectory.new(organization) : new
        end

        def organization
          nil
        end

        def people
          Actor.select("actors.*", "actors.external_id AS #{ID}")
        end

        def columns
          {}
        end

        def user(actor)
          User.new(actor, external_id: actor.has_attribute?(ID) ? actor[ID] : nil)
        end

        def save!(actor, external_id)
          actor.external_id = external_id
          actor.save!
        end

        def owned(actor_ids)
          actor_ids.to_set
        end

        def owned!(actor); end

        def proven!(actor); end

        def remove!(actor)
          keep_a_manager!(actor)

          held = { uuid: actor.uuid, identifier: actor.identifier, via: "scim" }

          actor.destroy!
          Event.record!(Event::ACTOR_DELETED, by: nil, **held)
        end

        def keep_a_manager!(actor)
          return unless actor.last_manager?

          raise Error.new(:conflict, "#{actor.identifier} is the last person who manages masks here", scim_type: "mutability")
        end
      end
    end
  end
end
