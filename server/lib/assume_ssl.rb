class AssumeSsl < ActionDispatch::AssumeSSL
  LOOPBACK = /\A(?:(?:.+\.)?localhost|127(?:\.\d{1,3}){3}|\[::1\])\z/i

  def self.loopback?(request)
    request.host.to_s.match?(LOOPBACK)
  end

  def call(env)
    self.class.loopback?(ActionDispatch::Request.new(env)) ? @app.call(env) : super
  end
end
