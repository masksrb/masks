class Release
  attr_reader :token, :connection_id

  def initialize(token:, connection_id:)
    @token = token
    @connection_id = connection_id.to_s
  end

  def connection
    return @connection if defined?(@connection)

    @connection = Connection.find_by(uuid: connection_id) if uuid?
  end

  def uuid?
    connection_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
  end

  def provider
    connection&.provider
  end

  def actor
    token.actor
  end

  def required_scope
    provider&.release_scope
  end

  def validate!
    ReleasePolicy.new(self).call
    self
  end

  def issue!
    { "access_token" => connection.release!, "connection" => connection.to_h }
  end
end
