module EventsHelper
  GRAVE = [
    Event::LOGIN_REFUSED,
    Event::LOGIN_THROTTLED,
    Event::REFRESH_REUSED,
    Event::DEVICE_BLOCKED,
    Event::AUTHENTICATOR_DISABLED,
    Event::PASSWORD_RESET_REQUESTED
  ].freeze

  def event_said(event)
    t("events.actions.#{event.action}", default: event.action)
  end

  def event_grave?(event)
    GRAVE.include?(event.action)
  end

  def event_where(event)
    [ event.device&.label, event.ip_address ].compact_blank.join(" · ")
  end
end
