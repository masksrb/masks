class AssumeSsl
  LOOPBACK = /\A(localhost|127(?:\.\d{1,3}){3}|\[::1\])\z/i

  def self.loopback?(request)
    request.host.to_s.match?(LOOPBACK) || request.host.to_s.downcase.end_with?(".localhost")
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    unless self.class.loopback?(ActionDispatch::Request.new(env))
      env["HTTPS"] = "on"
      env["HTTP_X_FORWARDED_PORT"] = "443"
      env["HTTP_X_FORWARDED_PROTO"] = "https"
      env["rack.url_scheme"] = "https"
    end

    @app.call(env)
  end
end
