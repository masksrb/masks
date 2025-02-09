require "test_helper"

class HardwareKeyMutationTest < GraphQLTestCase
  QUERY =
    "
      mutation ($input: HardwareKeyInput!) {
        hardwareKey(input: $input) {
          hardwareKey {
            id
            createdAt
          }

          errors
        }
      }
    "

  managers_only("phone", QUERY, input: {})

  test "managers can delete hardwareKeys" do
    log_in "manager"

    key =
      tester.hardware_keys.build(
        name: "test",
        public_key: "---",
        external_id: "123",
      )

    key.save!

    gql QUERY,
        input: {
          actorId: tester.key,
          id: key.external_id,
          action: "delete",
        }

    assert_not Masks::HardwareKey.find_by(external_id: key.external_id)
  end
end
