module Masks
  module LoginLinkHelper
    def code(link)
      "#{link.code_parts.first}&nbsp;#{link.code_parts.last}".html_safe
    end
  end
end
