module Masks
  module Server
    require "test_helper"

    class LdapBerTest < ActiveSupport::TestCase
      Ber = Ldap::Ber

      test "integers encode in the fewest two's complement bytes" do
        assert_equal "\x02\x01\x00".b, Ber.integer(0)
        assert_equal "\x02\x01\x7f".b, Ber.integer(127)
        assert_equal "\x02\x02\x00\x80".b, Ber.integer(128)
        assert_equal "\x02\x01\xff".b, Ber.integer(-1)
        assert_equal "\x02\x01\x80".b, Ber.integer(-128)
        assert_equal "\x02\x02\xff\x7f".b, Ber.integer(-129)
      end

      test "integers round trip" do
        [ 0, 1, 127, 128, 255, 256, 65_535, 2**31 - 1, -1, -128, -129, -(2**31) ].each do |number|
          assert_equal number, Ber.decode(Ber.integer(number)).integer
        end
      end

      test "long lengths use the long form" do
        encoded = Ber.octets("a" * 300)

        assert_equal "\x04\x82\x01\x2c".b, encoded.byteslice(0, 4)
        assert_equal "a" * 300, Ber.decode(encoded).string
      end

      test "sequences decode into their children" do
        element = Ber.decode(Ber.sequence([ Ber.integer(7), Ber.octets("hi"), Ber.boolean(true) ]))

        assert element.constructed?
        assert_equal [ 7, "hi", true ], [ element.child(0).integer, element.child(1).string, element.child(2).boolean ]
      end

      test "a message is read whole from a stream" do
        first = Ber.sequence([ Ber.integer(1) ])
        second = Ber.sequence([ Ber.integer(2) ])
        stream = StringIO.new(first + second)

        assert_equal 1, Ber.read(stream, limit: 100).child(0).integer
        assert_equal 2, Ber.read(stream, limit: 100).child(0).integer
        assert_nil Ber.read(stream, limit: 100)
      end

      test "a message larger than the limit is refused before it is read" do
        assert_raises(Ber::Error) { Ber.read(StringIO.new(Ber.octets("a" * 200)), limit: 100) }
      end

      test "a truncated stream is refused" do
        assert_raises(Ber::Error) { Ber.read(StringIO.new(Ber.octets("abc").byteslice(0, 3)), limit: 100) }
      end

      test "indefinite lengths are refused" do
        assert_raises(Ber::Error) { Ber.decode("\x30\x80\x00\x00".b) }
      end

      test "a child running past its parent is refused" do
        assert_raises(Ber::Error) { Ber.decode("\x30\x03\x04\x05abc".b) }
      end

      test "trailing bytes are refused" do
        assert_raises(Ber::Error) { Ber.decode(Ber.integer(1) + "\x00".b) }
      end

      test "deep nesting is refused" do
        nested = Ber.null
        40.times { nested = Ber.sequence([ nested ]) }

        assert_raises(Ber::Error) { Ber.decode(nested) }
      end

      test "high tag numbers are refused" do
        assert_raises(Ber::Error) { Ber.decode("\x1f\x81\x00\x00".b) }
      end

      test "an oversized integer is refused" do
        assert_raises(Ber::Error) { Ber.decode(Ber.tlv(Ber::INTEGER, "\x01" * 9)).integer }
      end

      test "asking for the wrong part is refused" do
        element = Ber.decode(Ber.sequence([ Ber.integer(1) ]))

        assert_raises(Ber::Error) { element.child(0, Ber::OCTET_STRING) }
        assert_raises(Ber::Error) { element.child(1) }
        assert_raises(Ber::Error) { element.string }
      end
    end
  end
end
