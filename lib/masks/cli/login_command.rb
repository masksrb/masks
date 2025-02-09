module Masks
  class LoginCommand < Masks::Command
    def initialize
      super do
        name default_name
        desc default_desc
      end
    end
  end
end
