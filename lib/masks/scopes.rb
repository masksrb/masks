module Masks
  class Scopes
    attr_reader :config

    OPENID = "openid"
    MANAGE = "masks:manage"
    DISCOVER_CLIENTS = "masks:clients:discover"
    REGISTER_CLIENTS = "masks:clients:register"

    class << self
      def yml
        @yml ||= Masks::Loader.yml("scopes")
      end

      def combine(v1, v2)
        (to_a(v1) + to_a(v2)).uniq
      end

      def filter(scopes, from)
        v1 = to_a(scopes)
        v2 = to_a(from)
        v2 - v1
      end

      def to_a(v)
        return [] unless v

        scopes =
          case v
          when String
            v.split("\n")
          when Array
            v
          else
            []
          end

        scopes
          .map { |line| line.split(" ") }
          .flatten
          .map { |line| line.split(",") }
          .flatten
          .compact
          .uniq
          .sort
      end

      def details(scopes)
        to_a(scopes).map { |scope| lookup(scope) } if scopes
      end

      def detail(name)
        lookup(name)[:detail]
      end

      def lookup(name)
        name = name.to_s

        @lookups ||= {}
        @lookups[name] ||= begin
          data = yml&.fetch(name, nil)
          hash = { scope: name, name: }

          case data
          when String
            hash[:detail] = data
          when Hash
            hash.merge!(**data.symbolize_keys)
          end

          hash[:hidden] = hash.key?(:hidden) ? hash[:hidden] : true
          hash
        end

        @lookups[name]
      end
    end

    def initialize(object, key)
      @object = object
      @key = key
    end

    def openid?
      has?(OPENID)
    end

    def masks_manager?
      has?(MANAGE)
    end

    def to_a
      self.class.to_a(@object.send(@key))
    end

    def combine(v)
      self.class.combine(to_a, v)
    end

    def has?(scope)
      to_a.include?(scope.to_s)
    end

    def all?(*scopes)
      scopes.all? { |scope| has?(scope) }
    end

    def assign(*list)
      @object.send("#{@key}=", self.class.combine(to_a, list))
    end

    def remove(*list)
      @object.send("#{@key}=", self.class.filter(to_a, list))
    end
  end
end
