module Masks
  module Server
    module Archivable
      extend ActiveSupport::Concern

      included do
        scope :active, -> { where(archived_at: nil) }
        scope :archived, -> { where.not(archived_at: nil) }
      end

      class_methods do
        def listed(archived)
          archived ? self.archived : active
        end
      end

      def archived?
        archived_at.present?
      end
    end
  end
end
