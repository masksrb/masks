module Masks
  module Server
    module Scim
      class OrganizationDirectory < Directory
        attr_reader :organization

        def initialize(organization)
          @organization = organization
        end

        def people
          Actor.joins(:memberships).merge(organization.memberships.accepted).select("actors.*", "memberships.external_id AS #{ID}")
        end

        def columns
          { "externalid" => "memberships.external_id" }
        end

        def save!(actor, external_id)
          membership = organization.memberships.find_by(actor: actor) unless actor.new_record?
          actor.updated_at = Time.current if membership && membership.external_id != external_id

          actor.save!

          membership ||= Members.enroll!(organization, actor, role: Organization::MEMBER, by: nil, provisioned: true, via: "scim")
          membership.update!(external_id: external_id) unless membership.external_id == external_id
        end

        def owned(actor_ids)
          return Set.new if actor_ids.empty?

          elsewhere = Membership.accepted.where(actor_id: actor_ids)
                                .where("organization_id <> ? OR NOT provisioned", organization.id).distinct.pluck(:actor_id)
          managers = Actor.where(id: actor_ids - elsewhere).select(&:manages?).map(&:id)

          (actor_ids - elsewhere - managers).to_set
        end

        def owned!(actor)
          return if owned([ actor.id ]).any?

          raise Error.new(:forbidden, "#{organization.name}'s directory did not create #{actor.identifier}, or they belong " \
                                      "elsewhere too, so it can remove them but not change them", scim_type: "mutability")
        end

        def proven!(actor)
          return if actor.email.blank? || proven_domains.include?(actor.email.split("@", 2).last)

          raise Error.new(:bad_request, "#{organization.name}'s directory sets only addresses at domains proven for #{organization.name}",
                          scim_type: "invalidValue")
        end

        def remove!(actor)
          membership = organization.memberships.find_by!(actor: actor)

          raise Error.new(:conflict, membership.errors.full_messages.to_sentence, scim_type: "mutability") unless membership.destroy

          Token.live.where(organization: organization, actor: actor).find_each(&:revoke!)
          Event.record!(Event::MEMBERSHIP_REMOVED, actor: actor, by: nil, organization: organization.key, via: "scim")
        end

        private

          def proven_domains
            @proven_domains ||= DomainClaim.verified.where(provider: organization.providers.active).order(:domain).pluck(:domain)
          end
      end
    end
  end
end
