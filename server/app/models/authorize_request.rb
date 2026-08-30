class AuthorizeRequest
  PATH = "/authorize".freeze

  attr_reader :request, :response, :error

  def initialize(params)
    @params = params
  end

  def run(&block)
    handler = Rack::OAuth2::Server::Authorize.new do |request, response|
      @request = request
      @response = response

      block.call(request, response)
    end

    @rack = handler.call(env)
    self
  rescue Rack::OAuth2::Server::Abstract::Error => error
    @error = error
    self
  end

  def refused?
    error.present?
  end

  def answered?
    @rack.present? && @rack.first.to_i != 200
  end

  def location
    @rack[1]["Location"] || @rack[1]["location"]
  end

  def approve!(code)
    response.code = code
    response.approve!
    response.finish
  end

  private

    def env
      {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => PATH,
        "QUERY_STRING" => Rack::Utils.build_query(@params),
        "rack.input" => StringIO.new("")
      }
    end
end
