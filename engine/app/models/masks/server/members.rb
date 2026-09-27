module Masks
  module Server
    module Members
      class Refused < StandardError; end

      class << self
        def add!(organization:, role:, by:, journey:, actor: nil, email: nil)
          raise Refused, "#{organization.name} is archived" if organization.archived?

          address = email.to_s.strip.downcase.presence
          actor ||= (address && Actor.find_by(email: address)) || invitee(address, by: by)

          raise Refused, "#{actor.identifier} is already a member of #{organization.name}" if organization.memberships.exists?(actor: actor)

          membership = organization.memberships.new(actor: actor, role: role, invited_by: by, pending: true, invited_as: address)

          raise Refused, membership.errors.full_messages.to_sentence unless membership.save

          Event.record!(Event::MEMBERSHIP_ADDED, actor: actor, by: by, organization: organization, role: role)

          sent = actor.activated? ? { delivered: false, url: nil } : invite(actor, journey)

          { membership: membership }.merge(sent)
        end

        def assign!(membership, role:, by:)
          was = membership.role

          return membership if was == role

          membership.role = role

          raise Refused, membership.errors.full_messages.to_sentence unless membership.save

          Event.record!(Event::MEMBERSHIP_ROLE_CHANGED, actor: membership.actor, by: by,
                                                        organization: membership.organization, was: was, now: role)

          membership
        end

        def remove!(membership, by:)
          raise Refused, membership.errors.full_messages.to_sentence unless membership.destroy

          organization = membership.organization

          Token.live.where(organization: organization, actor: membership.actor).find_each(&:revoke!)
          Event.record!(Event::MEMBERSHIP_REMOVED, actor: membership.actor, by: by,
                                                   organization: organization, role: membership.role)

          membership
        end

        private

          def invitee(email, by:)
            raise Refused, "an email address is required" if email.blank?

            actor = Actor.new(email: email, scopes: Scopes.join(Scopes::STANDARD))

            raise Refused, actor.errors.full_messages.to_sentence unless actor.save

            Event.record!(Event::ACTOR_CREATED, actor: actor, by: by, scopes: actor.scope_list, invited: true)

            actor
          end

          def invite(actor, journey)
            return { delivered: false, url: nil } if actor.email.blank?

            Invitations.open(actor: actor, journey: journey).slice(:delivered, :url)
          rescue Invitation::Refused
            { delivered: false, url: nil }
          end
      end
    end
  end
end
