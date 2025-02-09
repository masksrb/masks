class MasksTestCase < ActionDispatch::IntegrationTest
  setup do
    Masks.reset!
    DatabaseCleaner.clean

    @tester = nil
    @client = nil
    @manage_client = nil
    @manager = nil
    @user_agent = nil
    @rails_session = {}
    @entry_id = nil

    # Load seeds from install/db/seeds.rb, which includes a manager,
    # clients for management and dashboards, and little else.
    Rails.application.load_seed

    Masks.seed do
      actor nickname: "tester", email: "test@example.com", password: "password"
    end
  end

  class KeyGenerator
    def generate_key(secret, length = nil)
      SecureRandom.hex(length || 16)
    end
  end

  def rails_session
    @rails_session ||= {}
  end

  def manage_client
    @manage_client ||= Masks.installation.management_client
  end

  def manager
    @manager ||= Masks::Actor.find_by!(nickname: "manager")
  end

  def tester
    @tester ||= Masks::Actor.find_by!(nickname: "tester")
  end

  def make_actor
    Masks.signup("nick#{SecureRandom.alphanumeric(10)}").tap { |a| a.save! }
  end

  def make_client(name: nil)
    Masks::Client.create!(
      name: name || "client#{SecureRandom.alphanumeric(10)}",
    )
  end

  def make_device
    Masks::Device.create!(
      public_id: SecureRandom.uuid,
      ip_address: "127.0.0.1",
      user_agent:,
    )
  end

  def make_session
    Masks::SessionRecord.create!(data: "", session_id: SecureRandom.uuid)
  end

  def make_auth_code
    Masks::AuthorizationCode.create!(
      client: make_client,
      actor: make_actor,
      device: make_device,
    )
  end

  def make_access_token
    Masks::AccessToken.create!(
      client: make_client,
      actor: make_actor,
      device: make_device,
    )
  end

  def make_id_token
    Masks::IdToken.create!(
      client: make_client,
      actor: make_actor,
      device: make_device,
    )
  end

  def make_env(method = :get, path = "/", query = {}, session: nil)
    Masks
      .env
      .rack(method, path, query, session: session || rails_session)
      .merge(
        "HTTP_USER_AGENT" => user_agent,
        "action_dispatch.remote_ip" => "127.0.0.1",
        ActionDispatch::Cookies::GENERATOR_KEY => KeyGenerator.new,
        ActionDispatch::Cookies::COOKIES_ROTATIONS =>
          ActiveSupport::Messages::RotationConfiguration.new,
      )
  end

  def user_agent
    @user_agent ||= [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
      "AppleWebKit/605.1.15 (KHTML, like Gecko)",
      "Version/17.4 Safari/605.1.15",
    ].join(" ")
  end

  def iphone_ua!
    @user_agent = [
      "Mozilla/5.0 (iPhone14,3; U; CPU iPhone OS 15_0 like Mac OS X)",
      "AppleWebKit/602.1.50 (KHTML, like Gecko) Version/10.0 Mobile/19A346",
      "Safari/602.1",
    ].join(" ")
  end

  def firefox_ua!
    @user_agent = [
      "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:15.0)",
      "Gecko/20100101 Firefox/15.0.1",
    ].join(" ")
  end

  def get(*args, **opts, &block)
    super(
      *args,
      **opts.merge(headers: { "HTTP_USER_AGENT" => user_agent }),
      &block
    )
  end

  def post(*args, **opts, &block)
    super(
      *args,
      **opts.merge(headers: { "HTTP_USER_AGENT" => user_agent }),
      &block
    )
  end
end
