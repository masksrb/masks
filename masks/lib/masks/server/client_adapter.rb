module Masks
  class ServerBackend
    attr_reader :mode

    def initialize(mode)
      @mode = mode
    end

    def for_login(id)
      Masks::Client.find_by(key: id)
    end
  end
end
