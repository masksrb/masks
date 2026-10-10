module Masks
  module Rails
    module Privileged
      extend ActiveSupport::Concern
      include Masks::Rails::Configurable

      class_methods do
        def masked!(*privileges, **options)
          before_action(-> { authorize_masks!(*privileges) }, **options.slice(:only, :except))
        end
      end

      def authorize_masks!(*names)
        privileges = names.flatten.map { |name| masks_config.privilege(name) }

        masks_by_token? ? masks_authorize_token!(privileges) : masks_authorize_session!(privileges)
      end

      private

        def masks_by_token?
          return false unless respond_to?(:masks_authorize_token!, true)
          return true if request.authorization.present? || !respond_to?(:masks_authorize_session!, true)

          masks_tokens.nil?
        end
    end
  end
end
