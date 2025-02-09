module Masks
  module Sessions
    class Structure
      attr_reader :session

      def initialize(session)
        @session = session
        @bags = {}
        @opts = {}
      end

      def keys
        @bags.keys
      end

      def bag?(name)
        !!@opts[name.to_s]
      end

      def bag(name)
        name = name.to_s

        @bags[name] ||= if @opts[name]
          @opts[name][:cls].new(self, name, **@opts[name])
        end
      end

      def apply(&block)
        instance_exec(&block)
      end

      private

      def key(name, cls = SessionBag::Primitive, **opts)
        @opts[name.to_s] ||= {}
        @opts[name.to_s].merge!(opts.merge(cls:))
      end

      def current(name, **opts)
        key(name, SessionBag::Current, **opts)
      end

      def check(name, **opts)
        key(name, SessionBag::Check, **opts)
      end

      def device(type = Sessions::Device, **opts)
        key(
          opts.delete(:key) || :device,
          SessionBag::Device,
          **{ type:, **opts },
        )
      end
    end
  end
end
