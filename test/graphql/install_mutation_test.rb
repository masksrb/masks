require "test_helper"

class InstallMutationTest < GraphQLTestCase
  QUERY =
    "
      mutation ($input: InstallationInput!) {
        install(input: $input) {
          install {
            name
            url
            timezone
            region
            theme
            emails
            faviconUrl
            lightLogoUrl
            darkLogoUrl
            nicknames
            passwords
            backupCodes
            clients
            createdAt
            updatedAt
          }

          errors
        }
      }
  "

  managers_only("install", QUERY, input: {})

  test "current installation is returned" do
    log_in "manager"

    gql QUERY, input: {}

    assert_equal Masks.url, gql_result("install", "install", "url")
  end

  test "emails settings can be modified" do
    log_in "manager"

    gql QUERY,
        input: {
          emails: {
            smtp: {
              address: "example.com",
              userName: "test",
              password: "test",
            },
          },
        }

    assert_equal "example.com", Masks.setting(:emails, :smtp, :address)
    assert_equal "test", Masks.setting(:emails, :smtp, :user_name)
    assert_equal "test", Masks.setting(:emails, :smtp, :password)
  end

  test "certain settings mark the need for server restart" do
    log_in "manager"

    assert_not Masks.installation.reload.needs_restart

    gql QUERY,
        input: {
          sessions: {
            lifetime: "30 days",
          },
          devices: {
            lifetime: "30 days",
          },
        }

    assert Masks.installation.reload.needs_restart
  end

  test "server restart are necessary only when settings change" do
    log_in "manager"

    assert_not Masks.installation.reload.needs_restart

    gql QUERY, input: { devices: { lifetime: "400 days" } }

    assert_not Masks.installation.reload.needs_restart
  end
end
