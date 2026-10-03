module Masks
  module Server
    require "test_helper"

    class AuthorizationDetailsTest < ActiveSupport::TestCase
      def schema(**properties)
        AuthorizationDetails::Schema.new({ "type" => "object", "properties" => properties.deep_stringify_keys })
      end

      test "details are a JSON array of objects that each name a type" do
        assert_nil AuthorizationDetails.parse(nil)
        assert_equal [ "a" ], AuthorizationDetails.parse('[{"type":"a"}]').types

        [ "{}", "[]", '[{"no":"type"}]', "[1]", "not json", '[{"type":"has space"}]' ].each do |value|
          assert_raises(AuthorizationDetails::Invalid, value) { AuthorizationDetails.parse(value) }
        end
      end

      test "there is a ceiling on how many entries and how many bytes" do
        assert_raises(AuthorizationDetails::Invalid) { AuthorizationDetails.parse(Array.new(11) { { "type" => "a" } }) }
        assert_raises(AuthorizationDetails::Invalid) { AuthorizationDetails.parse([ { "type" => "a", "x" => "y" * 9.kilobytes } ]) }
      end

      test "a schema checks types, enums, lengths, ranges, and unknown fields" do
        checked = schema(actions: { type: "array", items: { type: "string", enum: %w[read write] }, maxItems: 2 },
                         count: { type: "integer", minimum: 1, maximum: 5 }, note: { type: "string", maxLength: 3 })

        assert_nil checked.problem({ "actions" => [ "read" ], "count" => 2 }, "t")
        assert_match "actions[0] must be one of", checked.problem({ "actions" => [ "delete" ] }, "t")
        assert_match "holds more than 2", checked.problem({ "actions" => %w[read write read] }, "t")
        assert_match "whole number", checked.problem({ "count" => 1.5 }, "t")
        assert_match "at most 5", checked.problem({ "count" => 9 }, "t")
        assert_match "longer than 3", checked.problem({ "note" => "long" }, "t")
        assert_match "does not accept other", checked.problem({ "other" => 1 }, "t")
      end

      test "a narrower request is covered by what was granted, whatever its key order" do
        granted = [ { "type" => "a", "x" => { "p" => 1, "q" => 2 } }, { "type" => "b" } ]

        assert AuthorizationDetails.parse([ { "x" => { "q" => 2, "p" => 1 }, "type" => "a" } ]).covered_by?(granted)
        assert_not AuthorizationDetails.parse([ { "type" => "a", "x" => { "p" => 1 } } ]).covered_by?(granted)
        assert_not AuthorizationDetails.parse([ { "type" => "c" } ]).covered_by?(nil)
      end

      test "a declaration needs a label and a schema masks can read" do
        good = { "label" => "Read", "schema" => { "type" => "object" } }

        assert AuthorizationDetails.check_declaration!("files" => good)

        [ { "files" => good.except("label") }, { "files" => good.merge("schema" => { "type" => "string" }) },
          { "files" => good.merge("schema" => { "type" => "object", "$ref" => "#/x" }) }, { "bad type" => good } ].each do |value|
          assert_raises(AuthorizationDetails::Invalid, value.inspect) { AuthorizationDetails.check_declaration!(value) }
        end
      end
    end
  end
end
