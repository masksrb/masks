module Masks
  class OneOfPolicy
    include Policy
    include RequestMatchers

    def apply(data, &block)
    end
  end
end
