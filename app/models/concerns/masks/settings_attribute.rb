module Masks
  module SettingsAttribute
    extend ActiveSupport::Concern

    class_methods do
      def parse_conf(key, conf, opts)
        parsed =
          case conf
          when Symbol, String
            { type: conf }
          when Array
            { type: conf[0], array: true }
          when Class
            {
              type: conf.to_s.split("::").last.underscore.to_sym,
              graphql: conf,
            }
          else
            conf
          end

        parsed.merge!(opts)
        parsed[:desc] ||= I18n.t("settings.#{self.name.underscore}.desc.#{key}")
        parsed[:graphql] ||= begin
          cls =
            case parsed[:type].to_s
            when "datetime"
              GraphQL::Types::ISO8601DateTime
            else
              "GraphQL::Types::#{parsed[:type].to_s.camelize}".constantize
            end

          parsed[:array] ? [cls] : cls
        end

        parsed
      end

      def readonly(**attrs)
        settings(attrs, writable: false)
      end

      def writable(**attrs)
        settings(
          attrs.except(:defined),
          writable: true,
          **attrs.slice(:defined),
        )
      end

      def all_settings
        { **writable_settings, **readonly_settings }
      end

      def writable_settings
        return unless @settings

        @settings[self.name].map { |k, v| [k, v] if v[:writable] }.compact.to_h
      end

      def readonly_settings
        return unless @settings

        @settings[self.name]
          .map { |k, v| [k, v] unless v[:writable] }
          .compact
          .to_h
      end

      def timestamps(*names)
        definition = { created_at: :datetime, updated_at: :datetime }

        names.each { |name| definition[name] = :datetime }

        settings(definition, writable: false, defined: true)
      end

      def settings(settings = nil, **config)
        if !settings
          settings = config
          config = {}
        end

        @settings ||= {}
        @settings[self.name] ||= {}

        settings.each do |key, conf|
          metadata = parse_conf(key, conf, config)

          @settings[self.name][key.to_s] = metadata

          existing =
            config[:defined] || try(:attribute_types)&.keys&.include?(key.to_s)

          unless existing
            unless method_defined?("#{key}")
              define_method key do
                setting(key, default: config[:default])
              end
            end

            unless method_defined?("#{key}=")
              define_method "#{key}=" do |value|
                self.settings ||= {}
                self.settings[key.to_s] = case metadata[:type]
                when :boolean
                  Masks.to_bool(value)
                else
                  value
                end
              end
            end

            unless method_defined?("#{key}?")
              define_method "#{key}?" do
                !!send(key)
              end
            end
          end
        end

        @settings[self.name]
      end
    end

    def setting(*names, default: nil)
      setting = (settings || {}).dig(*names.map(&:to_s))
      setting || default
    end

    def setting!(name, value)
      self.settings[name.to_s] = value
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
