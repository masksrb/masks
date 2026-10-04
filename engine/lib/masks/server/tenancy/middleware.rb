module Masks
  module Server
    module Tenancy
      class Middleware
        UNSERVED = "no tenant is served at this hostname".freeze
        CROWDED = "too many tenants were claimed recently; try again later".freeze
        CLAIM_WINDOW = 1.hour
        TENANTLESS = %w[/up].freeze
        TLS_ASK = "/tls/allowed".freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          request = ActionDispatch::Request.new(env)

          return @app.call(env) if TENANTLESS.include?(request.path)
          return allowed(request) if request.path == TLS_ASK

          tenant = Tenant.serving(request.host)

          return unserved unless tenant || templated?(request)

          tenant ||= Tenant.named(request.host)

          if tenant.nil?
            return crowded if Tenant.claiming? && crowded?(request)

            tenant = Tenant.claim(request.host)
          end

          return unserved if tenant.nil?

          origin = origin_for(request, tenant)

          return unserved if origin.nil?

          Current.origin = origin
          Current.ip_address = request.remote_ip
          Current.user_agent = request.user_agent

          Tenant.switch(tenant) { @app.call(env) }
        end

        private

          def templated?(request)
            template = ::Rails.configuration.masks.public_origin_template

            return true if template.nil?

            host_of(format(template, subdomain: request.host.to_s.split(".").first))&.casecmp?(request.host.to_s)
          end

          def host_of(origin)
            URI.parse(origin).host
          rescue URI::InvalidURIError
            nil
          end

          def origin_for(request, tenant)
            return "#{request.base_url}#{request.script_name}" if ::Rails.configuration.masks.public_origin_template.nil?
            return tenant.custom_origin if tenant.custom_host&.casecmp?(request.host.to_s)

            canonical = tenant.templated_origin

            canonical if host_of(canonical)&.casecmp?(request.host.to_s)
          end

          def allowed(request)
            served = Tenant.serving(request.params["domain"])

            [ served ? 200 : 404, { "content-type" => "text/plain; charset=utf-8", "cache-control" => "no-store" }, [] ]
          end

          def crowded?(request)
            window = Time.current.to_i / CLAIM_WINDOW.to_i
            from_here = ::Rails.cache.increment("tenant-claims:#{window}:#{request.remote_ip}", 1, expires_in: CLAIM_WINDOW)
            from_anywhere = ::Rails.cache.increment("tenant-claims:#{window}", 1, expires_in: CLAIM_WINDOW)

            from_here.to_i > ::Rails.configuration.masks.claim_limit ||
              from_anywhere.to_i > ::Rails.configuration.masks.claim_ceiling
          end

          def crowded
            [
              429,
              { "content-type" => "text/plain; charset=utf-8", "cache-control" => "no-store", "retry-after" => CLAIM_WINDOW.to_i.to_s },
              [ CROWDED ]
            ]
          end

          def unserved
            [
              404,
              { "content-type" => "text/plain; charset=utf-8", "cache-control" => "no-store" },
              [ UNSERVED ]
            ]
          end
      end
    end
  end
end
