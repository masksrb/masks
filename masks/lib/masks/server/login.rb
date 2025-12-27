module Masks
  class ServerLogin
    class PolicyError < RuntimeError
    end

    attr_reader :request

    def initialize
      @request = request
    end
  end
end
