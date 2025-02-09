module Masks
  module SessionBag
    class Device < Abstract
      def key
        [name.to_s, to_session_key(value)]
      end

      def last_key
        "#{name}:current"
      end

      def last_id
        container[last_key]
      end

      def replace(value)
        raise "cannot replace device"
      end

      def current
        value
      end

      def value
        @value ||= device_class.load(session, id)
      end

      def id
        @public_id ||=
          if last_id
            refresh!(last_id)
          elsif cookie_id
            cookie_id
          else
            reset_id!
          end
      end

      def reset!
        reset_id!

        @public_id = nil
        @value = nil
      end

      private

      def device_class
        args[:type]
      end

      def request
        session.rails_request
      end

      def refresh!(value)
        request.cookie_jar.signed[cookie_key] = {
          value:,
          expires: device_class.cleanup_at,
        }

        container[last_key] = value

        value
      end

      def reset_id!
        refresh!(SecureRandom.alphanumeric(32))
      end

      def cookie_id
        request.cookie_jar.signed[cookie_key]&.presence
      end

      def cookie_key
        device_class.cookie_key
      end
    end
  end
end
