module Masks
  module Adapter
    extend ActiveSupport::Concern

    included do
      include Masks::Settings

      attr_reader :key
      attr_accessor :settings

      setting :name, :string, default: -> { default_name }
    end

    class << self
      def build(name, settings)
        settings = settings.deep_stringify_keys
        j
        return unless settings

        cls =
          if settings["type"]
            "Masks::Adapters::#{settings["type"].classify}Adapter"
          elsif settings["class"]
            settings["class"]
          else
            "Masks::Adapters::#{name.classify}Adapter"
          end

        cls.constantize.new(name, settings.except(*(%w[type class])))
      end
    end

    class_methods do
      def type
        name.to_s.split("::").last.underscore.delete_suffix("_adapter")
      end
    end

    attr_accessor :deleted

    def initialize(key, settings)
      @key = key
      @settings = settings.deep_stringify_keys
    end

    def type
      self.class.type
    end

    def default_name
      key.titleize if key
    end

    def setup?
      self.class.settings.all? { |k, v| setting(k) || v[:optional] }
    end

    def config
      self.class.settings.map { |k, v| [k, setting(k)] }.to_h
    end
  end
end
