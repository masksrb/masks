module Masks
  class Mask
    attr_reader :opts

    def initialize(opts)
      @opts = opts
    end

    # def policy
      # @policy ||= begin
        # cls = case opts[:policy]
        # when Symbol
          # "Masks::#{opts[:policy].to_s.classify}Policy".constantize
        # else
          # opts[:policy]
        # end
      # end
    # end
  end
end
