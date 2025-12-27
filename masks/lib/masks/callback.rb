module Masks
  class Callback
    ENV_KEY = 'masks.callback'

    class << self
      def start(request)
        request.env[ENV_KEY] ||= new(request)
      end
    end

    attr_reader :request

    delegate :env, to: :request

    def initialize(request)
      @request = request
    end

    def masks(*masks)
      @masks ||= []

      if masks.any? && !@frozen
        masks.each do |mask|
          @masks.push(Masks::Mask.new(mask))
        end
      end

      self
    end

    def call(app)
      @frozen = true

      debugger
      @policies = @masks&.map do |mask|
        mask.policy.action(:policy)
      end

      @policies.each do |p|
        p.call(env.dup)
      end

      app.call(env)
    rescue PolicyFailure => e
      e.call(app)
    end
  end
end
