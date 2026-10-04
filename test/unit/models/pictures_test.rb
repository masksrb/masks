module Masks
  module Server
    require "test_helper"

    class PicturesTest < ActiveSupport::TestCase
      SVG = %(<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64"/></svg>).freeze

      test "only the four web image formats are decoded" do
        assert_raises(Pictures::Unreadable) { Pictures.square(SVG, 32) }
      end

      test "a png still becomes a square webp" do
        require "vips"

        png = Vips::Image.black(40, 20).pngsave_buffer
        square = Pictures.square(png, 16)

        assert_equal "image/webp", Pictures.sniff(square)
      end
    end
  end
end
