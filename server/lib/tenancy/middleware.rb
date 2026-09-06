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

      tenant = Tenant.resolve(request.host) || Tenant.claim(request.host)

      return unserved if tenant.nil?

      Current.origin = origin_for(request)
      Current.ip_address = request.remote_ip
      Current.user_agent = request.user_agent

      Tenant.switch(tenant) { @app.call(env) }
    end

    private

      def origin_for(request)
        template = Rails.configuration.masks.public_origin_template

        return request.base_url if template.nil?

        format(template, subdomain: request.host.split(".").first)
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
