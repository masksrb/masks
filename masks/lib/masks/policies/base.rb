module Masks
  class BasePolicy < AbstractPolicy
    attr_reader :policies

    def initialize(*policies, **opts, &block)
      @policies = []

      case policies
      when Masks::Policy
        add(*policies.policies, &block)
      when Array
        add(*policies, &block)
      when Hash
        add(policies, &block)
      else
        add(&block)
      end
    end

    def match(input)
      case input
      when ActionDispatch::Request
        match_request(input)
      end
    end

    private

    def match_request(request)
      # No policy for excluded paths (return nil)
      return if path_matches?(excluded, request.path)

      policy = self.class.new
      policies.each do |opts|
        next unless path_matches?(opts[:on], request.path)
        next unless method_matches?(opts[:method], request.method)
        next unless block_matches?(opts[:block], request)

        policy.add(opts)
      end

      policy
    end

    def path_matches?(matchers, path)
      Array.wrap(matchers).each do |matcher|
        case matcher
        when String
          if matcher == '*'
            return true
          elsif matcher.include?('*') && Fuzzyurl.matches?(matcher, path)
            return true
          else
            regexp = Regexp.new(Regexp.escape(matcher).gsub(%r{:([^/])+}, '(.+)').to_s)

            return true if regexp.match?(path)
          end
        when Regexp
          return true if matcher.match?(path)
        when nil
          return true
        end
      end

      false
    end

    def method_matches?(matcher, method)
      !matcher || Array(matcher).map(&:to_s).map(&:upcase).compact.include?(method&.to_s&.upcase)
    end

    def block_matches?(block, request)
      !block || block.call(request)
    end
  end
end
