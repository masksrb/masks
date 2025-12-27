module Masks
  module Sessions
    class Server
      ENV_KEY = "masks.session"

      class << self
        def current(request)
          request.env[ENV_KEY] ||= new(request)
        end
      end

      attr_reader :request
      attr_accessor :client

      def initialize(request)
        @request = request
      end

      def data
        request.session
      end

      include DeviceData
      include Throttle
    end
  end
end
