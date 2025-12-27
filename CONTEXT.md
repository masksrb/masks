# Session Context - 2026-01-16

## What we did

1. **Moved ideas → proposals** - Created `/docs/src/content/docs/proposals/` section in Astro/Starlight docs, moved `ideas/captcha-improvements.md` there, deleted old folder

2. **Created `Masks::Controller` concern** - Moved from `lib/masks/policies/controller.rb` to `lib/masks/controller.rb`, renamed from `Masks::Policies::Controller` to `Masks::Controller`

3. **Updated policy method signature** - `policy(type = :controller, class_name: :controller_policy, &block)` - allows shared policy types across controllers

4. **Wrote Policy-First Architecture proposal** - Major architectural document at `/proposals/controller-policy`

## Key Architecture Decisions

- **Policies extend `AbstractPolicy`** - no intermediate ControllerPolicy class
- **`on :request` runs in controller context** - where `Masks::Controller` is already included, so policies have access to `device`, `masks_session`, `stop`, `render`, `params`, `session`, `cookies`, `flash`
- **`default_policies` method** - instance method for policy composition, override to customize
- **No Rails-style action methods** - `on :request` block handles requests, branches on method
- **`inherits:`** - copies policies at definition time, no runtime chain
- **No Rails route integration** - Masks handles routes at middleware, client libs generate URLs
- **YML or Ruby config** - both supported, class lookups allow overrides at any layer
- **`Masks::Controller` concern** - for adding policy enforcement to existing Rails controllers (policies don't include it, they run in a context that has it)

## Files Changed

- `docs/src/content/docs/proposals/index.mdx` - proposals index
- `docs/src/content/docs/proposals/captcha-improvements.mdx` - moved from ideas
- `docs/src/content/docs/proposals/controller-policy.mdx` - policy-first architecture
- `masks/lib/masks/controller.rb` - new location for Masks::Controller concern
- Deleted: `ideas/`, `masks/lib/masks/policies/controller.rb`

## Config Pattern

```ruby
Masks.configure do
  policy :masks do
    device captcha: :turnstile
    login on: '/login'
    sso on: '/sso'
  end

  policy inherits: :masks do
    logged_in on: '/dashboard'
  end
end
```

## Policy Structure

```ruby
class Masks::LoginPolicy < Masks::AbstractPolicy
  def default_policies
    device
    client
    throttle after: 5
    captcha after: 3
  end

  on :request do |policy|
    case request.method
    when 'GET'
      render :new
    when 'POST'
      if authenticate(params)
        redirect_to after_login_path
      else
        render :new, status: :unprocessable_entity
      end
    end
  end
end
```

## Next Steps

- Implement `inherits:` keyword in policy DSL
- Build out LoginPolicy, SsoPolicy, OidcPolicy using new pattern
- Remove mode routing in favor of policy config
- Test `Masks::Controller` concern in Rails controllers
