module Masks
  module Client
    module Stores
      class Memory
        attr_reader :held

        def initialize(held = {})
          @held = held
        end

        def read
          held
        end

        def write(value)
          @held = value
        end
      end

      class Session
        def initialize(session, key)
          @session = session
          @key = key
        end

        def read
          @session[@key]
        end

        def write(value)
          if value.empty?
            @session.delete(@key)
          else
            @session[@key] = value
          end
        end
      end
    end
  end
end
