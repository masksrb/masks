module Masks
  class PolicyFailure < RuntimeError
    attr_reader :response

    def initialize(response)
      super

      @response = response
    end
  end

  module Policy
    extend ActiveSupport::Concern

    class_methods do
      def checks(matcher, &block)
        @checks ||= {}
        @checks[name] ||= {}
        @checks[name][matcher.to_s] ||= []
        @checks[name][matcher.to_s] << block if block_given?
        @checks[name][matcher.to_s]
      end
    end

    included do
      attr_reader :config
    end

    def initialize(**config, &block)
      @config = { at: '*' }.merge(config)
      before_init
      run(&block)
    end

    def run(&block)
      @dsl = true
      instance_exec(&block) if block_given?
      self
    ensure
      @dsl = false
    end

    def method_missing(type, *args, **opts, &block)
      if @dsl && respond_to?(:add)
        add(type, **opts, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @dsl || super
    end

    def copy(&block)
      p = dup
      p.run(&block) if block_given?
      p
    end

    def initialize_copy(source)
      super
      @config = source.config.dup
      after_copy(source)
    end

    def check(data, *extras, context: nil)
      args = []

      matchers = case data
      when Symbol, String
        args = extras
        self.class.checks(data)
      else
        args = [data, *extras]
        self.class.checks(data.class.name)
      end

      matchers&.each do |matcher|
        (context || self).instance_exec(*args, &matcher)
      end

      self
    end

    def context
      @context ||= {}
    end

    def action_matches?(_action)
      true
    end

    def excluded
      @excluded ||= []
    end

    def exclude(*paths)
      excluded.push(*paths)
      self
    end

    protected

    def before_init
      # Override me
    end

    def after_copy(source)
      # Override me
    end
  end
end
