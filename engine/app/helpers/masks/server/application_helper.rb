module Masks
  module Server
    module ApplicationHelper
      def vite_manifest
        Server.engine? ? Server.vite_ruby.manifest : super
      end

      private

        def scope_key_by_partial(key)
          super.sub(/\A(layouts\.)?masks\.server\./, '\1')
        end
    end
  end
end
