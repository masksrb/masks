ENV["RAILS_ENV"] = "test"

require_relative "support/host"
require "rails/test_help"

primary, masks = %w[primary masks].map { |name| ActiveRecord::Base.configurations.configs_for(env_name: "test", name: name) }
ActiveRecord::Tasks::DatabaseTasks.create(primary)
ActiveRecord::Tasks::DatabaseTasks.create(masks)
ActiveRecord::Tasks::DatabaseTasks.purge(masks)
ActiveRecord::Base.establish_connection(masks)
ActiveRecord::Base.connection_pool.migration_context.migrate
ActiveRecord::Base.establish_connection(primary)
Masks::Server::Tenant.declare!

Masks::Server.instance_variable_set(:@vite_ruby, ViteRuby.new(root: ENV.fetch("MASKS_SERVER_ROOT", "/rails"), mode: "test"))

class EngineModeTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password".freeze

  def tenant
    @tenant ||= Masks::Server::Tenant.find_by!(subdomain: "app")
  end

  def create_actor(nickname: "ada-#{SecureRandom.hex(3)}")
    Masks::Server::Tenant.switch(tenant) { Masks::Server::Actor.create!(nickname: nickname, password: PASSWORD) }
  end

  def sign_in(actor, path: "/auth")
    post "#{path}/login", params: { event: "identify", identifier: actor.nickname }, as: :json
    post "#{path}/login", params: { event: "password", password: PASSWORD }, as: :json
    JSON.parse(response.body)
  end

  teardown { Masks::Server::Tenant.clear! }
end
