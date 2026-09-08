require_relative "test_helper"

class LoadingTest < Minitest::Test
  SCRIPT = 'require "masks"; ' \
           "print [ defined?(Masks::Client::Session), defined?(Masks::Rails) ].inspect"

  def test_the_rails_half_stays_out_of_a_plain_ruby_process
    assert_equal '["constant", nil]', loaded
  end

  private

    def loaded
      lib = File.expand_path("../../client/lib", __dir__)

      IO.popen([ RbConfig.ruby, "-I#{lib}", "-e", SCRIPT ], &:read)
    end
end
