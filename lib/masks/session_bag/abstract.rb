module Masks
  module SessionBag
    class Abstract
      include ActiveSupport::Delegation

      attr_reader :structure, :session, :name, :args

      def initialize(structure, name, **args)
        @structure = structure
        @session = structure.session
        @name = name.to_s
        @args = { expiry: session.request_id }.merge(args)
      end

      def parent
        @args[:parent]
      end

      def container
        parent ? session.structure.bag(parent).data : session.data
      end

      def parent_path
        parent ? session.structure.bag(parent).full_path : nil
      end

      def full_path
        [parent_path, path].flatten.compact
      end

      def path
        Array(key).flatten.compact
      end

      def key
        raise NotImplementedError
      end

      def data
        return if args[:null] && path.none?

        raise KeyError, "'#{name}' key is empty" unless path.any?

        hash = container

        path.each do |p|
          hash[p] ||= {}
          session.deep_clean(hash[p])
          hash = hash[p]
        end

        hash[Session::EXPIRY_KEY] ||= lifetime
        hash
      end

      def expiry=(value)
        args[:expiry] = value
      end

      def lifetime
        resolve_expiry(args[:expiry])
      end

      def refresh(*args)
        data[Session::EXPIRY_KEY] = (
          if args.length == 1
            resolve_expiry(args[0])
          else
            lifetime
          end
        )
      end

      def expired?
        Masks.time.expired?(expiry)
      end

      def expires_at
        data[Session::EXPIRY_KEY]
      end

      def expire
        data&.clear
      end

      def update(value)
        expire
        data.merge!(value)
        refresh
      end

      def [](key)
        return if args[:null] && !data

        data[key.to_s]
      end

      def []=(key, value)
        data[key.to_s] = value
      end

      def value
        data
      end

      private

      def resolve_expiry(value)
        value = session.instance_exec(&value) if value.respond_to?(:call)

        case value
        when Time
          value.iso8601
        else
          value
        end
      end

      def to_session_key(value)
        value.respond_to?(:session_key) ? value.session_key : value
      end
    end
  end
end
