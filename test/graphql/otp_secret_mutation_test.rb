require "test_helper"

class OtpSecretMutationTest < GraphQLTestCase
  QUERY =
    "
      mutation ($input: OtpSecretInput!) {
        otpSecret(input: $input) {
          otpSecret {
            id
            createdAt
          }

          errors
        }
      }
    "

  managers_only("otpSecret", QUERY, input: {})

  test "managers can delete otpSecrets" do
    log_in "manager"

    secret = tester.otp_secrets.create!(name: "test")

    gql QUERY,
        input: {
          actorId: tester.key,
          id: secret.public_id,
          action: "delete",
        }

    assert_not Masks::OtpSecret.find_by(public_id: secret.public_id)
  end
end
