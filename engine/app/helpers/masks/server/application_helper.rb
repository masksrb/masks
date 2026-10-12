module Masks
  module Server
    module ApplicationHelper
      def tenant_mark(tenant, size: 64)
        return tag.span(tenant&.name.to_s.first&.upcase, class: "auth-mark", "aria-hidden": true) unless tenant&.logo_url

        tag.img(src: tenant.logo_url(size: size), alt: "", class: "auth-mark auth-mark-logo")
      end

      def tenant_accent(tenant)
        accent = tenant&.accent
        return if accent.nil?

        tag.style(<<~CSS.html_safe)
          .auth-page {
            --signal: #{accent};
            --signal-ink: #{tenant.accent_ink};
            --label: #{accent};
            --brass: #{accent};
            --ring: color-mix(in oklab, #{accent} 30%, transparent);
          }
        CSS
      end
      def vite_manifest
        Server.engine? ? Server.vite_ruby.manifest : super
      end

      def flashed?(organization = nil)
        flash[:organization] == organization&.key && (flash[:alert].present? || flash[:notice].present?)
      end

      private

        def scope_key_by_partial(key)
          super.sub(/\A(layouts\.)?masks\.server\./, '\1')
        end
    end
  end
end
