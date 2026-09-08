class NotificationJob < ApplicationJob
  queue_as :mailers

  def perform(event_id, origin: nil)
    event = Event.includes(:actor, :client, :device, :by).find_by(id: event_id)

    return if event.nil?

    Current.origin ||= origin

    Notifications.deliver(event)
  end
end
