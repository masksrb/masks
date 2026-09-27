module Masks
  module Server
    module Members
      class Refused < StandardError; end

      DAILY_INVITATIONS = 50
      RESEND_AFTER = 1.hour
      INVITED = [ Event::MEMBERSHIP_ADDED, Event::MEMBERSHIP_RESENT ].freeze
      NOT_SENT = { delivered: false, url: nil }.freeze

      class << self
        def add!(organization:, role:, by:, journey:, actor: nil, email: nil, manager: false)
          raise Refused, "#{organization.name} is archived" if organization.archived?

          address = email.to_s.strip.downcase.presence
          policy = SignInPolicy.for(organization: organization)

          invitable!(organization, address, by: by, policy: policy) unless manager

          actor ||= (address && Actor.find_by(email: address)) || invitee(address, by: by, policy: policy)

          if organization.memberships.exists?(actor: actor)
            raise Refused, "#{address || actor.identifier} is already a member of #{organization.name}"
          end

          membership = enroll!(organization, actor, role: role, by: by, pending: true, invited_as: address)

          sent = actor.activated? ? tell(membership, journey) : invite(actor, journey, membership)

          { membership: membership }.merge(sent)
        end

        def enroll!(organization, actor, role:, by:, pending: false, invited_as: nil, provisioned: false, **details)
          membership = organization.memberships.new(actor: actor, role: role, invited_by: by, pending: pending,
                                                    invited_as: invited_as, provisioned: provisioned)

          Membership.transaction do
            raise Refused, membership.errors.full_messages.to_sentence unless membership.save

            Event.record!(Event::MEMBERSHIP_ADDED, actor: actor, by: by, organization: organization, role: role, **details)
          end

          membership
        end

        def assign!(membership, role:, by:, **details)
          organization = membership.organization
          was = nil

          organization.with_lock do
            membership.reload
            was = membership.role

            next if was == role

            membership.role = role

            raise Refused, membership.errors.full_messages.to_sentence unless membership.save

            AccessToken.live.where(organization: organization, actor: membership.actor).find_each(&:revoke!)
            Event.record!(Event::MEMBERSHIP_ROLE_CHANGED, actor: membership.actor, by: by,
                                                          organization: organization, was: was, now: role, **details)
          end

          membership
        end

        def remove!(membership, by:)
          organization = membership.organization

          organization.with_lock do
            raise Refused, membership.errors.full_messages.to_sentence unless membership.destroy

            Token.live.where(organization: organization, actor: membership.actor).find_each(&:revoke!)
            Event.record!(Event::MEMBERSHIP_REMOVED, actor: membership.actor, by: by,
                                                     organization: organization, role: membership.role)
          end

          membership
        end

        def resend!(membership, by:, journey:, manager: false)
          organization = membership.organization

          raise Refused, "#{label(membership) || 'that person'} has already joined #{organization.name}" unless membership.pending?
          raise Refused, "#{organization.name} is archived" if organization.archived?
          raise Refused, "that invitation was sent less than an hour ago" if membership.invited_at&.after?(RESEND_AFTER.ago)

          capped!(by) unless manager

          membership.update!(invited_at: Time.current)
          Event.record!(Event::MEMBERSHIP_RESENT, actor: membership.actor, by: by, organization: organization,
                                                  role: membership.role)

          sent = membership.actor.activated? ? tell(membership, journey) : invite(membership.actor, journey, membership)

          { membership: membership }.merge(sent)
        end

        def purge_lapsed!
          Membership.lapsed(Membership.lifetime.ago).includes(:organization, :actor).find_each do |membership|
            membership.destroy!
            Event.record!(Event::MEMBERSHIP_EXPIRED, actor: membership.actor, by: nil, organization: membership.organization,
                                                     role: membership.role, invited_as: membership.invited_as)
          end
        end

        def label(membership)
          membership.pending? ? membership.invited_as : membership.actor.identifier
        end

        private

          def invitable!(organization, address, by:, policy:)
            raise Refused, "an email address is required" if address.nil?

            capped!(by)

            return if proven?(organization, address)
            return if policy.signup && policy.admits?(address)

            raise Refused, "#{organization.name} can add people at a domain it has proven, or anyone while sign-up is open; " \
                           "ask a manager to add #{address}"
          end

          def capped!(by)
            return if Event.where(action: INVITED, by: by, created_at: 1.day.ago..).count < DAILY_INVITATIONS

            raise Refused, "you have sent #{DAILY_INVITATIONS} invitations today; a manager can add more"
          end

          def proven?(organization, address)
            DomainClaim.for_email(address)&.provider&.organization_id == organization.id
          end

          def invitee(email, by:, policy:)
            raise Refused, "an email address is required" if email.blank?

            actor = Actor.new(email: email, scopes: Scopes.join(policy.signup_scope_list))

            raise Refused, actor.errors.full_messages.to_sentence unless actor.save

            Event.record!(Event::ACTOR_CREATED, actor: actor, by: by, scopes: actor.scope_list, invited: true)

            actor
          end

          def invite(actor, journey, membership)
            return NOT_SENT if actor.email.blank?

            Invitations.open(actor: actor, journey: journey, membership: membership).slice(:delivered, :url)
          rescue Invitation::Refused
            NOT_SENT
          end

          def tell(membership, journey)
            return NOT_SENT unless Notifications.mailable?(membership.actor) && membership.acceptable?

            ActorMailer.organization_invitation(membership, journey: journey).deliver_later

            { delivered: true, url: nil }
          end
      end
    end
  end
end
