module Masks
  module SessionBag
    class Current < Abstract
      include Enumerable

      CURRENT_KEY = "__current__"

      def each
        all.each do |k, v|
          unless k.start_with?("_")
            yield(
              self.class.new(
                @structure,
                name,
                **args.merge(track: false, current: k),
              )
            )
          end
        end
      end

      def keys
        all.keys.filter { |k| !k.start_with?("_") }
      end

      def values
        all.map { |k, v| [k, v] unless k.start_with?("_") }.compact.to_h
      end

      def value
        self.current
      end

      def replace(value)
        self.current = value
      end

      def current=(value)
        @current = nil

        args[:current] = value

        if args[:track] && computed_key != tracked
          all[CURRENT_KEY] = computed_key

          refresh if value
        end
      end

      def current
        @current || args[:current]
      end

      def all
        container[name.to_s] ||= {}
      end

      def tracked
        all[CURRENT_KEY]
      end

      def key
        return unless current

        [name.to_s, computed_key]
      end

      def computed_key
        current.respond_to?(:session_key) ? current&.try(:session_key) : current
      end

      def lifetime
        if current&.respond_to?(:session_lifetime)
          args[:expiry] = current.session_lifetime || args[:expiry]
        end

        super
      end

      def with(current)
        self.class.new(@structure, @name, **@args.merge(current:))
      end

      delegate :merge, :merge!, :dig, :fetch, to: :data, allow_nil: true
    end
  end
end
