<p align="center"><img src="https://raw.githubusercontent.com/masksrb/masks/main/engine/public/masks-public/icon.svg" width="120" alt="The masks rose window"></p>

# masks

Sign people in to a Ruby or Rails app with a [masks](https://github.com/masksrb/masks) server, and
accept the tokens it gives out.

The gem has two parts:

- `Masks::Rails`, a Rails engine that adds sign-in to your app. It loads only when Rails does.
- `Masks::Client`, plain Ruby for any app. It depends on `jwt` and nothing else.

## Install

```ruby
gem "masks"
```

The gem needs Ruby 3.2 or later.

## Rails

1. Run the install generator:

   ```sh
   bin/rails generate masks:install --resource https://app.example.com
   ```

2. Set `MASKS_ISSUER` to the masks server and tenant you sign in against.
3. Start the app and open `/auth/handshake`.
4. Approve the app on the masks server.

Then require a sign-in in a controller:

```ruby
class DashboardController < ApplicationController
  include Masks::Rails::Authentication

  masked!

  def index
    @name = masked.name
  end
end
```

## Any Ruby app

```ruby
session = Masks::Client::Session.new(
  issuer: "https://demo.auth.example.com",
  client_id: id, client_secret: secret,
  redirect_uri: "https://app.example.com/auth/callback"
)

started = session.start
tokens = session.complete(code: params[:code], verifier: started[:verifier])
identity = session.identity(tokens)
```

Keep `started[:state]`, `started[:nonce]`, and `started[:verifier]` in the session, and send the
browser to `started[:url]`. When it comes back, check `state` and `identity["nonce"]` against the
values you kept.

## Documentation

- [Rails apps](https://masks.pages.dev/reference/ruby/) covers the handshake, privileges,
  organizations, accepting tokens, and running several processes.
- [Masks::Client](https://masks.pages.dev/reference/ruby/client/) and
  [Masks::Rails](https://masks.pages.dev/reference/ruby/rails/) list every class and setting.

## License

MIT.
