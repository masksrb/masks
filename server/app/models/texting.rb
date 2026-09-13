module Texting
  def self.deliverable?
    Current.tenant&.texts? || false
  end

  def self.deliver_later(to:, body:)
    return false unless deliverable?

    TextJob.perform_later(to, body)
    true
  end
end
