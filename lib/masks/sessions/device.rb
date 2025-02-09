module Masks
  module Sessions
    class Device
      attr_reader :session

      class << self
        def load(session, id)
          new(session, id)
        end

        def cleanup_at
          nil
        end

        def cookie_key
          "_device"
        end
      end

      def initialize(session, id)
        @session = session
        @id = id
      end

      def public_id
        @id
      end

      def session_key
        [version, @id].join(":")
      end

      def logout!
        refresh_version
      end

      private

      def version
        @session.rails_session["device_version"] ||= refresh_version
      end

      def refresh_version
        @session.rails_session["device_version"] = SecureRandom.hex(3)
      end
    end
  end
end
