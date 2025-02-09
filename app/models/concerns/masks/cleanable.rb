module Masks
  module Cleanable
    extend ActiveSupport::Concern

    class_methods do
      def cleanup(column, &block)
        @cleanup_column = column
        @cleanup_block = block
      end

      def cleanup_column
        @cleanup_column
      end

      def cleanup_duration
        @cleanup_block&.call
      end

      def cleanup_at
        duration = cleanup_duration
        Time.current + duration if duration
      end

      def cleanup_after
        duration = cleanup_duration
        Time.current - duration if duration
      end

      def cleanable
        if cleanup_column
          where(arel_table[cleanup_column].lt(cleanup_after))
        else
          raise NotImplementedError
        end
      end
    end

    def cleanable?
      if col = self.class.cleanup_column
        self[col] < self.class.cleanup_after
      else
        raise NotImplementedError
      end
    end

    def cleanup
      destroy
    end
  end
end
