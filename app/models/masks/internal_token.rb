# frozen_string_literal: true

module Masks
  class InternalToken < Token
    cleanup :expires_at do
      0.seconds
    end

    def code
      key
    end
  end
end
