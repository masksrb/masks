module Masks
  module Server
    module Tenancy
      class Middleware
        UNSERVED = "no tenant is served at this hostname".freeze
        TENANTLESS = %w[/up].freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          request = ActionDispatch::Request.new(env)

          return @app.call(env) if TENANTLESS.include?(request.path)
          return unserved unless templated?(request)

          tenant = Tenant.resolve(request.host) || Tenant.claim(request.host)

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

            canonical = tenant.public_origin

            canonical if host_of(canonical)&.casecmp?(request.host.to_s)
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
