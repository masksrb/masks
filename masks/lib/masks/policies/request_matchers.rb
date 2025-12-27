module Masks
  module RequestMatchers
    def request_matches?(request)
      path_matches?(request.path) && method_matches?(request.method) && block_matches?(request)
    end

    def path_matches?(path, matchers = nil)
      Array.wrap(matchers || config[:at]).each do |matcher|
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

    def method_matches?(method)
      !config[:method] || Array(config[:method]).map(&:to_s).map(&:upcase).compact.include?(method&.to_s&.upcase)
    end

    def block_matches?(request)
      !config[:block] || config[:block].call(request)
    end
  end
end
