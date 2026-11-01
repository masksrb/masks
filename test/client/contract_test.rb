require_relative "test_helper"

class ContractTest < Minitest::Test
  TABLE = JSON.parse(File.read(File.expand_path("../contract/errors.json", __dir__)))

  def test_every_failure_in_the_contract_is_worded_the_same
    TABLE["failures"].each do |key, held|
      names = held["description"].scan(/\{[a-z_]+\}/)
      values = names.map { |name| name[1..-2].upcase }
      description = names.zip(values).reduce(held["description"]) { |text, (name, value)| text.sub(name, value) }

      assert_equal [ held["code"], description ], Masks::Client.failure(key, *values), key
    end
  end

  def test_a_refusal_and_a_challenge_read_as_masks_code_description
    assert_equal "masks: invalid_grant: that code expired", Masks::Client::Rejected.new("invalid_grant", "that code expired").message
    assert_equal "masks: insufficient_scope: this token does not carry files", Masks::Client::Forbidden.new(*Masks::Client.failure("no_scope", "files")).message
  end
end
