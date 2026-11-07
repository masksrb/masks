module Masks
  module Server
    class Actor
      module Notices
        extend ActiveSupport::Concern

        def notified?(action)
          Notifications.mailed?(action) && (Notifications.always?(action) || !muted_notifications.include?(action.to_s))
        end

        def notifications
          Notifications::MAILED - muted_notifications
        end

        def notifications=(wanted)
          self.muted_notifications = Notifications::MUTABLE - Array(wanted).map(&:to_s)
        end
      end
    end
  end
end
