module Masks
  class Seeder
    attr_reader :install

    def initialize(install)
      @install = install
    end

    def actor(key, **opts)
      Masks::Actor.seed!(key:, **opts)
    end

    def client(key, **opts)
      Masks::Client.seed!(key:, **opts)
    end

    def provider(key, **opts)
      Masks::Provider.seed!(key:, **opts)
    end
  end
end
