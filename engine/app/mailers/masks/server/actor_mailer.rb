module Masks
  module Server
    class ActorMailer < ApplicationMailer
      def invitation(actor, url, journey:, membership: nil)
        return message unless deliverable?

        journey!(journey)
        @actor = actor
        @url = url
        @organization = membership&.organization
        @lede = membership ? organization_lede(membership) : tenant_lede(journey.manager)

        mail(
          from: self.class.from,
          to: actor.email,
          subject: membership ? organization_subject(membership) : t("actor_mailer.invitation.subject", tenant: @tenant_name)
        )
      end

      def organization_invitation(membership, journey:)
        return message unless deliverable?

        journey!(journey)
        @actor = membership.actor
        @organization = membership.organization
        @role = membership.role
        @lede = organization_lede(membership)
        @url = home && "#{home}#organization-#{@organization.key}"

        mail(from: self.class.from, to: @actor.email, subject: organization_subject(membership))
      end

      def password_reset(actor, url, journey:)
        return message unless deliverable?

        journey!(journey)
        @actor = actor
        @url = url
        @opened_by = journey.manager

        mail(
          from: self.class.from,
          to: actor.email,
          subject: t("actor_mailer.password_reset.subject", tenant: @tenant_name)
        )
      end

      def notification(actor, event, journey:)
        return message unless deliverable?

        journey!(journey)
        told = Notifications.told(event, @tenant_name)

        @actor = actor
        @event = event
        @said = t("actor_mailer.notification.said.#{event.action}", **told, default: Notifications.said(event))
        @wrong = t("actor_mailer.notification.wrong_for.#{event.action}", **told, default: t("actor_mailer.notification.wrong"))
        @where = Notifications.where(event)
        @at = Notifications.at(event, actor)
        @by = event.by if event.by && event.by_id != actor.id
        @url = home
        @settings = home && "#{home}#notifications"

        mail(
          from: self.class.from,
          to: actor.email,
          subject: t("actor_mailer.notification.subject", said: Notifications.said(event), tenant: @tenant_name)
        )
      end

      def email_verification(actor, url, journey:)
        return message unless deliverable?

        journey!(journey)
        @actor = actor
        @url = url

        mail(
          from: self.class.from,
          to: actor.email,
          subject: t("actor_mailer.email_verification.subject", tenant: @tenant_name)
        )
      end

      def confirmation_code(email, code, journey:)
        return message unless deliverable?

        journey!(journey)
        @code = code

        mail(
          from: self.class.from,
          to: email,
          subject: t("actor_mailer.confirmation_code.subject", code: code, tenant: @heading)
        )
      end

      def approval_requested(manager, actor, journey:)
        return message unless deliverable?

        journey!(journey)
        @actor = actor
        @url = journey.origin.presence && "#{journey.origin}/manage/actors/#{actor.uuid}"

        mail(
          from: self.class.from,
          to: manager.email,
          subject: t("actor_mailer.approval_requested.subject", nickname: actor.identifier, tenant: @tenant_name)
        )
      end

      def idle(actor, due:, notice:, journey:)
        return message unless deliverable?

        journey!(journey)
        @actor = actor
        @due = I18n.l(due.to_date, format: :long)
        @notice = notice
        @keeps = notice != IdleAccounts::DELETE_SUSPENDED
        @url = @keeps && home

        mail(
          from: self.class.from,
          to: actor.email,
          subject: t("actor_mailer.idle.subject.#{@keeps ? 'active' : 'suspended'}", tenant: @tenant_name)
        )
      end

      def approved(actor, journey:)
        return message unless deliverable?

        journey!(journey)
        @actor = actor
        @url = home

        mail(
          from: self.class.from,
          to: actor.email,
          subject: t("actor_mailer.approved.subject", tenant: @tenant_name)
        )
      end

      private

        def tenant_lede(manager)
          return t("actor_mailer.invitation.invited", tenant: @tenant_name) if manager.nil?

          t("actor_mailer.invitation.invited_by", nickname: manager.identifier, tenant: @tenant_name)
        end

        def organization_lede(membership)
          named = { organization: membership.organization.name, role: membership.role }

          return t("actor_mailer.organization_invitation.invited", **named) if membership.invited_by.nil?

          t("actor_mailer.organization_invitation.invited_by", nickname: membership.invited_by.identifier, **named)
        end

        def organization_subject(membership)
          t("actor_mailer.organization_invitation.subject", organization: membership.organization.name)
        end
    end
  end
end
