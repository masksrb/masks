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

  KINDS = {
    "Refused" => Masks::Client::Refused,
    "InvalidToken" => Masks::Client::InvalidToken,
    "Forbidden" => Masks::Client::Forbidden,
    "Unavailable" => Masks::Client::Unavailable,
    "Insecure" => Masks::Client::Insecure,
    "Foreign" => Masks::Client::Foreign,
    "DelegationRefused" => Masks::Client::Delegations::Refused,
    "DelegationUnavailable" => Masks::Client::Delegations::Unavailable
  }.freeze

  def test_every_kind_in_the_contract_is_a_masks_error_with_its_ruby_name
    TABLE["kinds"].each do |kind|
      assert_equal kind["names"]["ruby"], KINDS.fetch(kind["name"]).name
      assert_operator KINDS.fetch(kind["name"]), :<, Masks::Client::Error
    end
  end

  def test_every_failure_in_the_contract_is_raised_with_its_code_and_description
    TABLE["failures"].each do |key, held|
      names = held["description"].scan(/\{[a-z_]+\}/)
      values = names.map { |name| name[1..-2].upcase }
      description = names.zip(values).reduce(held["description"]) { |text, (name, value)| text.sub(name, value) }
      klass = KINDS.fetch(held["kind"])
      error = klass.respond_to?(:of) ? klass.of(key, *values) : klass.new(Masks::Client.saying(key, *values))

      assert_kind_of Masks::Client::Error, error, key
      assert_equal held["code"], error.code, key
      assert_equal description, error.description, key
      assert_equal "masks: #{held['code']}: #{description}", error.message, key
    end
  end

  def test_a_missing_token_is_the_one_failure_that_says_so
    assert_predicate Masks::Client::InvalidToken.of("no_token"), :missing?
    refute_predicate Masks::Client::InvalidToken.of("expired"), :missing?
  end

  def test_a_refusal_and_a_challenge_read_as_masks_code_description
    assert_equal "masks: invalid_grant: that code expired", Masks::Client::Refused.new("invalid_grant", "that code expired").message
    assert_equal "masks: insufficient_scope: this token does not carry files", Masks::Client::Forbidden.new(*Masks::Client.failure("no_scope", "files")).message
  end
end
