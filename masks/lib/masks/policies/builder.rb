module Masks
  class PolicyBuilder
    attr_reader :policies, :config

    def initialize(*args, **opts, &block)
      @policies = []
      @config = {}.merge(opts)

      run(&block) if block_given?
    end

    def dup
      self.class.new(**@config).tap do |dup|
        policies.each do |builder|
          dup.add(builder)
        end
      end
    end

    def match(request)
      if path_matches?(request.path, excluded)
        return
      end

      self.class.new(**@config).tap do |dup|
        policies.each do |builder|
          dup.add(builder) if request_matches?(request)
        end
      end
    end

    def request_matches?(request)
      path_matches?(request.path) && method_matches?(request.method) && block_matches?(request)
    end

    def path_matches?(path, matchers = nil)
      Array.wrap(matchers || config[:on]).each do |matcher|
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

    def type
      config[:type]&.to_s
    end

    def class_name
      Masks.mode.class_name("#{type}_policy")
    end

    def excluded
      @excluded ||= []
    end

    def exclude(*paths)
      excluded.push(*paths)

      self
    end

    def resolve
      class_name.new(self)
    end

    def run(&block)
      @dsl = true
      instance_exec(&block)
      @dsl = false
    end

    def add(type, **opts, &block)
      case type
      when Symbol, String
        @policies << self.class.new(**({ on: '*', type: }.merge(opts)), &block)
      when Hash
        @policies << self.class.new(**type.merge(opts), &block)
      when self.class
        @policies << type
      end

      self
    end
  end
end
