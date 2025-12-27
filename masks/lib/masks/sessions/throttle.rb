module Masks
  module Sessions
    module Throttle
      extend ActiveSupport::Concern

      THROTTLE_KEY = 'masks.throttles'

      def throttle
        @throttle ||= ThrottleData.new(data)
      end

      class ThrottleData
        def initialize(session_data)
          @data = session_data
        end

        def exceeded?(key, limit:)
          count(key) >= limit
        end

        def count(key)
          throttles[key.to_s] || 0
        end

        def increment(key)
          throttles[key.to_s] = count(key) + 1
        end

        def reset(key)
          throttles[key.to_s] = 0
        end

        private

        def throttles
          @data[THROTTLE_KEY] ||= {}
        end
      end
    end
  end
end
