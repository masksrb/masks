class ErrorPages < ActionDispatch::PublicExceptions
  ORIGINAL_METHOD = "action_dispatch.original_request_method".freeze

  def call(env)
    return super unless env[ORIGINAL_METHOD] == "HEAD"

    status, headers, = super(env.merge(ORIGINAL_METHOD => "GET"))
    [ status, headers, [] ]
  end
end
