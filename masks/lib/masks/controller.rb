module Masks
  module Controller
    extend ActiveSupport::Concern

    class Stopped < RuntimeError
      attr_reader :name, :status, :policy, :assigns, :debug

      def initialize(error, status:, policy: nil, assigns: {}, **opts)
        super error

        @name = error
        @status = status
        @policy = policy
        @assigns = assigns
        @debug = opts[:debug]
      end
    end

    class_methods do
      def masks_policy(*args)
        @masks_policy ||= args[0] if args.any?
        @masks_policy
      end

      def mask(name, **opts, &block)
        masks[name] << [name, opts, block]
      end

      def masks
        @masks ||= {}
        @masks[name] ||= []
      end
    end

    included do
      layout :masks_layout

      include Rails.application.routes.url_helpers
      include Masks::Sessions::Controller

      rescue_from Stopped, with: :render_masks

      before_action :masked!
      helper_method :masks_policy, :masks_session, :device, :masks_dev?
    end

    private

    def masks_policy
      @masks_policy ||= begin
        Masks.policy(self.class.masks_policy || :controller).dup
      end
    end

    def masked!
      self.class.masks.each do |mask|
        args = [mask[0]].compact
        opts = mask[1] || {}
        block = mask[2]

        if block
          masks_policy.add(*args, **opts, &block)
        else
          masks_policy.add(*args, **opts)
        end
      end

      masks_policy.check(:request, context: self)
    end

    def masks_layout
      Masks.mode.client_layout
    end

    def stop(error, status: 401, policy: nil, debug: nil, assigns: {})
      raise Stopped.new(error, status:, policy:, assigns:, debug:)
    end

    def render_masks(error)
      @mode = Masks.mode
      @policy = error.policy
      @client = masks_session.client
      @device = masks_session.device
      @debug = masks_debug.tap do |debug|
        debug.message = error.debug
      end

      # Set any additional assigns from the policy
      error.assigns.each do |key, value|
        instance_variable_set("@#{key}", value)
      end

      view = "#{@policy.class.name.underscore}/#{error.name}"
      status = error.status || 401

      respond_to do |format|
        format.html do
          render(view, status: status)
        end

        format.json do
          render json: { error: error.name }, status: status
        end
      end
    end
  end
end
