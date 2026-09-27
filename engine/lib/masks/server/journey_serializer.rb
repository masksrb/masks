module Masks
  module Server
    class JourneySerializer < ActiveJob::Serializers::ObjectSerializer
      def serialize(journey)
        super(journey.dump)
      end

      def deserialize(held)
        Journey.load(held)
      end

      def klass
        Journey
      end
    end
  end
end
