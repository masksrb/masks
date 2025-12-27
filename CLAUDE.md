# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Masks is a monorepo for an authentication and authorization framework built as a Ruby on Rails engine. **The main codebase lives in `masks/`** - almost all code changes will be in this directory.

### Project Structure

- **`masks/`** - Main Rails engine (all core functionality)
  - `lib/masks/policies/` - Policy system for request middleware and authorization
  - `app/controllers/masks/` - Controllers including MiddlewareController
  - `app/frontend/` - Svelte 5 components
  - `app/models/` - Core models (Actor, Client, Device, Provider)
  - `test/dummy/` - Test Rails application
- `container/` - Docker container configuration
- `docs/` - Astro-based documentation site
- `examples/client/` - Example client application

### Tech Stack

- **Backend:** Rails 8.1, Ruby 3.4.7, SQLite, GraphQL
- **Frontend:** Svelte 5, Vite 7, Tailwind CSS 4, DaisyUI 5, TypeScript
- **Tools:** Mise (version management), Overmind (process manager)

## Development Commands

All commands run from `masks/` directory:

```bash
# Development
npm run dev              # Start Vite + Rails via Overmind
npm run dev:reset        # Reset database and run migrations
npm run dev:fresh        # Full reset and start dev

# Testing
npm run test             # Run Rails tests
bin/rails test           # Run all tests directly
bin/rails test test/path/to/test.rb          # Run single test file
bin/rails test test/path/to/test.rb:42       # Run single test at line

# Building
npm run build            # Build frontend with Vite

# Formatting & Linting
npm run format           # Format all code (Ruby + JS/Svelte)
npm run lint             # Check formatting
npm run rubocop:fmt      # Format Ruby only
npm run prettier:fmt     # Format JS/Svelte only
```

## Middleware Architecture

Masks is a Rails engine that intercepts requests via middleware before they reach the main application.

### Request Flow

```
Request → Masks::Routing::Middleware → MiddlewareController → Policy Checks
                                                                    ↓
                                              [FAIL] → Render error response
                                              [PASS] → Continue to downstream Rails controller
```

1. **Middleware** (`lib/masks/routing/middleware.rb`) - Rack middleware that intercepts all enabled routes
2. **MiddlewareController** - A Rails controller invoked by the middleware, runs policy checks
3. **Policies** - If any policy fails, MiddlewareController renders a response and the request stops
4. **Pass-through** - If all policies pass, the original request continues to the downstream controller

### Session Conflict Issue

**Important architectural constraint:** Both MiddlewareController and downstream controllers can manipulate the Rails session. With cookie-based sessions, this creates conflicts:
- MiddlewareController modifies session (e.g., throttle counts)
- Request passes through to downstream controller
- Downstream controller also modifies session
- Competing `Set-Cookie` headers or one overwrites the other

**Solutions:**
- Use database-backed sessions (ActiveRecord session store)
- Store middleware state in the Device model instead of session
- Avoid session writes in MiddlewareController when passing through

## Policy System Architecture

The policy system is the core abstraction for handling request authorization and middleware logic.

### Key Components

1. **AbstractPolicy** (`lib/masks/policies/abstract.rb`) - Base class with `on` DSL for event handlers, path/method/block matching
2. **RequestPolicy** (`lib/masks/policies/request.rb`) - Entry point, orchestrates sub-policies
3. **MiddlewareController** (`app/controllers/masks/middleware_controller.rb`) - Rails controller as middleware, calls `Masks.policy(:request).apply(self)`
4. **Sub-Policies** (ClientPolicy, DevicePolicy, LoggedInPolicy) - Specific authorization concerns

### Policy DSL

Policies configured in `config/masks.rb`:

```ruby
Masks.configure do
  policy do
    client
    device captcha: :turnstile
    logged_in on: '/protected'
  end
end
```

### Captcha Configuration

The device policy supports captcha verification with throttling:

```ruby
device captcha: :turnstile                     # always require (default)
device captcha: :recaptcha, after: 5           # after 5 requests
device captcha: :hcaptcha, after: { get: 5 }   # 5 GETs allowed, others immediate
device captcha: :turnstile, after: { get: 5, default: 0 }
```

**Providers** (`lib/masks/captchas/`):
- `turnstile` - Cloudflare Turnstile (truly invisible)
- `recaptcha` - Google reCAPTCHA (variants: enterprise, v3, v2_checkbox, v2_invisible)
- `hcaptcha` - hCaptcha (variants: checkbox, invisible)

Each provider needs `sitekey` and `secret` configured in `masks.yml`.

### The `on` Pattern

```ruby
# In RequestPolicy - handles controller events
on Masks::MiddlewareController do |controller|
  matches.each do |policy|
    policy.apply(:request, self, context: controller)
  end
end

# In sub-policies - receives policy, self is controller
on "Masks::RequestPolicy" do |policy|
  client = find_client
  masks_session.client = client
  stop :error, policy: policy unless client
end
```

### Available in Policy Handlers

When running in controller context:
- `stop(error, status: 401)` - Halt request processing
- `request`, `session`, `params` - Standard Rails objects
- `masks_session` - Current Masks session with `.client`, `.device`
- `device` - Shortcut to `masks_session.device`
- `throttle!(key)` - Increment throttle counter
- `throttle!(key, reset: true)` - Reset throttle counter
- `throttled?(key, limit:)` - Check if throttle exceeded

### Policy Matching

```ruby
client key: :my_client, on: '/api/*', method: [:get, :post]
```

Uses `AbstractPolicy#path_matches?`, `method_matches?`, and `block_matches?`.

## Code Standards

- Use `on` abstraction for policies (not deprecated `controller do` blocks)
- Policies should be small, focused, and composable
- Test policies in `test/dummy/config/masks.rb`

## Testing

- Test application: `masks/test/dummy/`
- Policy configuration: `test/dummy/config/masks.rb`
- Routes: `test/dummy/config/routes.rb`
