module Masks
  module Routing
    class Middleware
      class << self
        def excluded_paths=(v)
          @excluded_paths = excluded_paths.append(v).flatten.compact.uniq
        end

        def excluded_paths
          @excluded_paths ||= []
        end

        def mask(path, **opts, &block)
          @masks ||= {}
          @masks[path] ||= { block: block, **opts }
        end

        def masks
          @masks
        end
      end

      def initialize(app)
        @app = app
      end

      def excluded_path?(path)
        @excluded_paths ||=
          self
            .class
            .excluded_paths
            .map do |path|
              case path
              when String
                Regexp.new("#{Regexp.escape(path).gsub(%r{:([^/])+}, "(.+)")}")
              end
            end
            .compact

        @excluded_paths.any? { |regexp| regexp.match?(path) }
      end

      def match_path?(matcher, path)
        if path.include?("*")
          Fuzzyurl.matches?(matcher, path)
        else
          matcher.delete_suffix("/") == path.delete_suffix("/")
        end
      end

      def call(env)
        # Not sure. works...
        ::Rails.application.reload_routes! unless ::Rails.env.production?
        ::Rails.application.reload_routes! unless ::Rails.env.production?

        masked = self.class.masks
        request = ActionDispatch::Request.new(env)

        if masked && !excluded_path?(request.path)
          masked.each do |path, mask|
            next unless match_path?(path, request.path)

            method_match =
              !mask[:method] || Array(mask[:method]).include?(request.method)

            next unless method_match

            endpoint =
              env["masks.endpoint"] = Masks::ProtectedEndpoint.new(@app, **mask)

            return endpoint.call(env)
          end
        end

        @app.call(env)
      end
    end
  end
end
