# frozen_string_literal: true

module Masks
  module Settings
    extend ActiveSupport::Concern

    class Description
      def initialize(owner, &block)
        @owner = owner
        @block = block
      end

      def to_s
        @to_s ||= @owner.instance_exec(&@block) || ''
      end

      def as_json
        to_s
      end
    end

    class CastValue
      def initialize(owner, &block)
        @owner = owner
        @block = block
      end

      def call(value)
        @owner.instance_exec(value, &@block)
      end

      def as_json
        nil
      end

      def to_s
        ''
      end
    end

    class_methods do
      def readonly(**attrs)
        settings(attrs, writable: false, readonly: true)
      end

      def writable(**attrs)
        settings(
          attrs.except(:defined),
          writable: true,
          **attrs.slice(:defined)
        )
      end

      def all_settings
        { **writable_settings, **readonly_settings }
      end

      def writable_settings
        return unless @settings

        @settings[name].filter_map { |k, v| [k, v] if v[:writable] }.to_h
      end

      def readonly_settings
        return unless @settings

        @settings[name]
          .filter_map { |k, v| [k, v] unless v[:writable] }
          .to_h
      end

      def timestamps(*names)
        definition = { created_at: :datetime, updated_at: :datetime }

        names.each { |name| definition[name] = :datetime }

        settings(definition, readonly: true)
      end

      def cast_value(type, value)
        case type
        when :boolean
          Masks.to_bool(value)
        else
          value
        end
      end

      def setting_i18n(name, key, default:)
        I18n.t("settings.#{self.name.underscore}.#{key}.#{name}", default:)
      end

      def setting(name, type, **opts)
        @settings ||= {}
        @settings[self.name] ||= if superclass.respond_to?(:settings)
                                   superclass.settings.dup
                                 else
                                   {}
                                 end

        conf =
          case type
          when Symbol, String
            { type: }
          when Array
            { type: type[0], array: true }
          when Class
            {
              type: type.to_s.split('::').last.underscore.to_sym,
              graphql: type
            }
          else
            type
          end

        conf.merge!(opts)
        conf[:desc] ||= Description.new(self) do
          setting_i18n(name, 'desc', default: '')
        end

        conf[:cast] = CastValue.new(self) do |value|
          cast_value(conf[:type], value)
        end

        conf[:primitive] ||= begin
          conf[:type]&.to_s&.classify
        rescue StandardError
          nil
        end

        conf[:attr] = try(:attribute_types)&.key?(name.to_s)
        conf[:graphql] ||= begin
          cls =
            if conf[:type].to_s == 'datetime'
              'GraphQL::Types::ISO8601DateTime'
            elsif conf[:type].to_s == 'json'
              'Masks::Types::CamelizedJson'
            else
              "GraphQL::Types::#{conf[:type].to_s.camelize}"
            end

          conf[:array] ? [cls] : cls
        end

        @settings[self.name][name.to_s] = conf

        existing =
          conf[:defined] || try(:attribute_types)&.key?(name.to_s)

        unless existing
          unless method_defined?(name.to_s)
            define_method name do
              setting(name)
            end
          end

          unless method_defined?("#{name}=")
            define_method "#{name}=" do |value|
              setting!(name, value)
            end
          end

          unless method_defined?("#{name}?")
            define_method "#{name}?" do
              !!send(name)
            end
          end
        end

        @settings[self.name]
      end

      def settings(settings = nil, **config)
        @settings ||= {}
        @settings[name] ||= {}

        unless settings
          settings = config
          config = {}
        end

        settings.each { |key, type| setting(key, type, **config) }

        @settings[name]
      end

      def settings_json
        return {} unless settings

        settings
          .map do |k, v|
            default = v[:default]
            default =
              case default
              when Proc
                'dynamic'
              when nil
                'null'
              when Integer, String
                default.to_s
              else
                default
              end

            [k, v.merge(default: setting_i18n(k, 'default', default:))]
          end
          .to_h
      end
    end

    def setting(name)
      conf = setting_conf(name)
      env =
        (ENV[conf[:env]&.to_s || conf[:env_only]&.to_s]&.presence if conf[:env] || conf[:env_only])

      return env || setting_default(name) if conf[:env_only]

      return self[name] ||= setting_default(name) if conf[:attr]

      keys = setting_keys(name)

      exists =
        if keys.length == 1
          settings.key?(keys[0])
        else
          settings.dig(*keys.slice(0...-1))&.key?(keys.last)
        end

      if exists
        self.class.cast_value(conf[:type], settings.dig(*keys))
      elsif env
        self.class.cast_value(conf[:type], env)
      else
        setting_default(name)
      end
    end

    def setting_default(name)
      conf = setting_conf(name)
      default = conf[:default]
      default.respond_to?(:call) ? instance_exec(&default) : default
    end

    def setting!(name, value)
      conf = setting_conf(name)

      return setting(name) if conf[:env_only]

      return self[name] = self.class.cast_value(conf[:type], value) if conf[
        :attr
      ]

      keys = setting_keys(name)
      data = settings

      keys.slice(0...-1).each { |key| data = data[key] ||= {} }

      data[keys.last] = value
    end

    def setting_conf(name)
      self.settings ||= {}
      self.class.settings.fetch(name.to_s)
    end

    def setting_keys(name)
      conf = setting_conf(name)
      keys = conf[:key] ? Array(conf[:key]).map(&:to_s) : [name.to_s]
      keys[0] = "#{setting_prefix}#{keys[0]}"
      keys
    end

    def setting_prefix
      ''
    end

    def merge_settings(updates)
      updates =
        if self.class.settings.keys.any?
          updates.deep_stringify_keys.slice(*self.class.settings.keys)
        else
          updates.deep_stringify_keys
        end

      self.settings = self.settings.deep_stringify_keys.deep_merge(updates)
    end
  end
end
