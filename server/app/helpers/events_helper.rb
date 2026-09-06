module EventsHelper
  WORRYING = (Event::GRAVE + [ Event::PASSWORD_RESET_REQUESTED ]).freeze

  def event_said(event)
    t("events.actions.#{event.action}", default: event.action)
  end

  def event_grave?(event)
    WORRYING.include?(event.action)
  end

  def event_where(event)
    [ event.device&.label, event.ip_address ].compact_blank.join(" · ")
  end
end
