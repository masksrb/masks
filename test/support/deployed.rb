module Masks
  module Server
    module Deployed
      def deployed
        ::Rails.env.define_singleton_method(:local?) { false }

        yield
      ensure
        ::Rails.env.singleton_class.remove_method(:local?)
      end

      def resolving(*addresses)
        held = addresses.map { |address| Addrinfo.tcp(address, 443) }
        original = Addrinfo.method(:getaddrinfo)

        Addrinfo.define_singleton_method(:getaddrinfo) { |*| held }

        yield
      ensure
        Addrinfo.define_singleton_method(:getaddrinfo, original)
      end
    end
  end
end
