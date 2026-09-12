module Notifications
  GROUPS = {
    "password" => [
      Event::PASSWORD_CHANGED,
      Event::PASSWORD_RESET_COMPLETED
    ],
    "factors" => [
      Event::PASSKEY_ADDED,
      Event::PASSKEY_REMOVED,
      Event::BACKUP_CODES_GENERATED,
      Event::BACKUP_CODE_SPENT,
      Event::AUTHENTICATOR_DISABLED
    ],
    "sessions" => [
      Event::SESSION_STARTED,
      Event::SESSION_REVOKED,
      Event::DEVICE_BLOCKED
    ],
    "applications" => [
      Event::CONSENT_GRANTED,
      Event::CONNECTION_LINKED,
      Event::CONNECTION_UNLINKED,
      Event::DEVICE_CODE_APPROVED
    ],
    "account" => [
      Event::ACTOR_SCOPES_CHANGED
    ]
  }.freeze

  MAILED = GROUPS.values.flatten.freeze

  ONCE_PER_DEVICE = [ Event::SESSION_STARTED ].freeze

  class << self
    def mailed?(action)
      MAILED.include?(action.to_s)
    end

    def raised(event)
      return false unless mailed?(event.action)
      return false unless event.actor_id && ActorMailer.deliverable?

      NotificationJob.perform_later(event.id, origin: Current.origin)
      true
    end

    def deliver(event)
      actor = event.actor

      return false unless mailable?(actor)
      return false unless actor.notified?(event.action)
      return false unless worth_saying?(event)

      ActorMailer.notification(
        actor, event,
        tenant_name: Current.tenant&.name,
        origin: Current.origin
      ).deliver_now

      true
    end

    def mailable?(actor)
      ActorMailer.deliverable? &&
        actor.present? &&
        actor.activated? &&
        actor.email.present? &&
        actor.email_verified_at.present?
    end

    def worth_saying?(event)
      return true unless ONCE_PER_DEVICE.include?(event.action)
      return true if event.device_id.nil?

      !Event.where(actor_id: event.actor_id, device_id: event.device_id, action: event.action)
            .where("id < ?", event.id)
            .exists?
    end

    def said(event)
      I18n.t("events.actions.#{event.action}", default: event.action)
    end

    def told(event, tenant_name)
      {
        tenant: tenant_name,
        nickname: event.actor&.identifier,
        client: event.client&.name,
        device: event.device&.label,
        by: event.by&.identifier,
        provider: provider_name(event),
        remaining: detail(event, "remaining"),
        passkey: detail(event, "passkey")
      }
    end

    def where(event)
      [ event.device&.label, event.ip_address ].compact_blank.join(" · ")
    end

    def at(event, actor)
      zone = ActiveSupport::TimeZone[actor.zoneinfo.to_s] || ActiveSupport::TimeZone["UTC"]

      event.created_at.in_time_zone(zone)
    end

    private

      def detail(event, key)
        (event.details || {})[key]
      end

      def provider_name(event)
        key = detail(event, "provider")

        key.presence && (Provider.find_by(key: key)&.name || key)
      end
  end
end
