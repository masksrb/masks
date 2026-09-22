module Masks
  module Server
    module ApplicationHelper
      private

        def scope_key_by_partial(key)
          super.sub(/\A(layouts\.)?masks\.server\./, '\1')
        end
    end
  end
end
