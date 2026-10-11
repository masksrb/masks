module Masks
  module Server
    require "test_helper"

    class ManageCopyTest < ActiveSupport::TestCase
      FRONTEND = Pathname.new(Dir.pwd).join("app/frontend/manage")
      USED = /\bt\(\s*["'`]([a-z0-9_.]+)["'`]/

      test "every key the console asks for has English wording" do
        missing = FRONTEND.glob("**/*.{svelte,js}").flat_map do |file|
          file.read.scan(USED).flatten.reject { |key| I18n.exists?("manage.#{key}", :en) }.map { |key| "#{key} (#{file.basename})" }
        end

        assert_empty missing
      end
    end
  end
end
