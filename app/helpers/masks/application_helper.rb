module Masks
  module ApplicationHelper
    def vite_manifest
      Masks::Engine.vite_ruby.manifest
    end
  end
end
