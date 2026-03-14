Derived from analysis of the Fizzy reference codebase (Rails 8.1). Follow these patterns strictly.

## Models

### Concern Composition

Models are composed of focused concerns. The model file reads as a declaration of capabilities:

```ruby
class Property < ApplicationRecord
  include Visible, Auditable, Searchable
  # Only associations/callbacks that don't belong to a specific concern
end
```

Two tiers:
- **Shared concerns** in `app/models/concerns/` — included by multiple models (Visible, Auditable, Searchable)
- **Model-namespaced concerns** in `app/models/[model]/` — specific to one model but extracted for clarity

### Concern Structure

Every concern follows this exact pattern:

```ruby
module Card::Closeable
  extend ActiveSupport::Concern

  included do
    # Associations, scopes, callbacks, enums, delegates
  end

  # Public instance methods

  private
    # Private methods (2-space indent under private keyword)
end
```

### Associations

- `belongs_to :creator, class_name: "User", default: -> { Current.user }` — defaults to current user
- `dependent: :delete_all` on join tables (not `:destroy`) when callbacks aren't needed
- `touch: true` on belongs_to for cache busting
- Ordering lambdas on has_many: `has_many :activities, -> { order(:created_at) }`

### Scopes

Named after what they return, not how they work:
- Temporal: `reverse_chronologically`, `chronologically`
- Existence-based: `where.missing(:closure)` for "open" items
- Eager-loading: `preloaded` scope chains all includes — never eager load in controllers

### Validations

- In models, not controllers
- `normalizes` macro for email/string cleanup before validation
- Multi-step forms use `ActiveModel::Model` with named validation contexts: `validates :name, presence: true, on: :completion`

### Callbacks

- `after_create_commit` (not `after_create`) for async job dispatch — avoids double-dispatch on rollback
- `before_save :method, if: :condition?` for conditional callbacks
- Lambda form for simple callbacks: `after_save -> { board.touch }, if: :published?`

### Enums

Declared with string storage. Avoid default integer storage:

```ruby
enum :status, %w[draft active under_offer sold withdrawn].index_by(&:itself)
enum :role, %w[admin partner_contact agent viewer].index_by(&:itself), scopes: false
```

## Controllers

### Thin Controllers

Controllers coordinate only. No inline conditionals, calculations, or data transformations beyond param reading. The model's API must be expressive enough that controller actions read as high-level descriptions:

```ruby
def create
  @comment = @card.comments.create!(comment_params)
end

def update
  @card.update!(card_params)
end
```

When an action maps to domain behavior, the model exposes a named method:

```ruby
def create # Cards::ClosuresController
  @card.close
end
```

### ApplicationController

Purely a concern compositor — no inline code:

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include CurrentRequest
end
```

### Strong Params

Use Rails 8 `params.expect` syntax:

```ruby
def property_params
  params.expect(property: [:title, :description, :listing_type, :price_amount])
end
```

### before_action Patterns

- `set_*` methods scope through `Current.user.accessible_*` — access control via scoping, not separate checks
- `only:` lists always explicit — no bare `before_action`
- Extract shared setup into controller concerns: `PropertyScoped`, `ReferralScoped`
- 404 (RecordNotFound) preferred over 403 — don't reveal existence of inaccessible records

### Namespacing

Namespace by domain, not just resource hierarchy:
- `Admin::UsersController` — Hamptons admin actions
- `Api::V1::PropertiesController` — JSON API
- `Partners::PropertiesController` — Partner-scoped views
- `My::ReferralsController` — Current user's own resources
- `Public::BrandedPagesController` — Unauthenticated access

### Rate Limiting

```ruby
rate_limit to: 10, within: 3.minutes, only: :create, with: :rate_limit_exceeded
```

## Views

### Layout Structure

- `content_for :header` — page-specific header (title, action buttons)
- `@page_title` instance variable for `<title>` tag
- Flash wrapped in `turbo_frame_tag :flash` for stream replacement

### Partials

- `_resource.html.erb` — single record rendering
- Subdirectories for display contexts: `properties/display/_card.html.erb`, `properties/display/_list_item.html.erb`
- Complex components use nested partial directories

### Caching

- `<% cache record do %>` wraps expensive partials
- Cache keys based on record's `cache_key`
- Comment cache bump dates when markup changes: `<%# Cache bump 2026-03-12 %>`

## Turbo Frames & Streams

### Frames

- Lazy-loaded: `turbo_frame_tag "section", src: path, loading: :lazy`
- Composite IDs: `turbo_frame_tag record, :edit` for inline editing
- `data-turbo-permanent` on elements surviving navigation (nav, footer frames)
- `refresh: :morph` on frames that should morph on refresh

### Streams

- Every `format.turbo_stream` has a `.turbo_stream.erb` view file
- Multi-target streams: one action can update multiple page regions
- `method: :morph` preferred for complex element replacement
- Flash via stream: `turbo_stream.replace(:flash, partial: "layouts/shared/flash")`
- Broadcasts from models: `broadcasts_refreshes` or `broadcast_prepend_later_to`

## Stimulus Controllers

### Structure

```javascript
export default class extends Controller {
  static targets = ["input", "output"]
  static values = { url: String, debounce: { type: Number, default: 300 } }

  connect() { }
  disconnect() { }

  // Public action methods
  submit() { }

  // Private methods use # prefix
  #save() { }
}
```

### Conventions

- File: `auto_save_controller.js` → `data-controller="auto-save"`
- Small, focused controllers — one responsibility each
- Cross-controller communication via `this.dispatch("event")`
- Shared utilities in `app/javascript/helpers/`
- Values API for Ruby → JS configuration
- `disconnect()` for cleanup (cancel timers, submit pending forms)

## Background Jobs

### Pattern: Shallow Delegation

Jobs accept an AR record and call a method on it. Logic lives in the model:

```ruby
class NotifyRecipientsJob < ApplicationJob
  discard_on ActiveJob::DeserializationError
  def perform(notifiable)
    notifiable.notify_recipients
  end
end
```

### Conventions

- `discard_on ActiveJob::DeserializationError` on every job accepting AR models
- `_later` suffix on model method that enqueues; no suffix on the method that does the work
- `after_create_commit :notify_recipients_later` — enqueue in commit callback
- Queue names: `default`, `mailers`, `pdf_generation`, `notifications`
- Error handling extracted into job concerns (e.g., `SmtpDeliveryErrorHandling`)

## Authentication & Permissions

### HClub uses password-based auth (not magic links like Fizzy)

- Rails 8 auth generator provides the base
- `Current.user` and `Current.organisation` available everywhere
- Account lockout after 5 failed attempts

### Permission Enforcement

- **Primary mechanism**: Scope queries through user-accessible records. If user lacks access, `RecordNotFound` (404)
- **Policy classes**: `PropertyPolicy`, `ReferralPolicy`, etc. — hand-rolled, Pundit-style
- **Visible concern**: `scope :visible_to, ->(user)` on every model with org-scoped data
- **Controller concern**: `before_action :authorize!` checks policy on every action
- User role predicates in model: `hamptons_admin?`, `partner_contact?`, `agent?`

## Testing

### Structure

- Minitest with `test "description" do` blocks
- `fixtures :all` loaded in every test
- `Current.session` set in `setup`, cleared in `teardown`
- Test files mirror `app/` exactly
- Parallel test execution

### Key Patterns

- `assert_difference -> { expr }, +N` for counting
- `assert_changes -> { expr }, from: X, to: Y` for state transitions
- `sign_in_as(user)` helper for integration tests
- Multi-tier fixtures: admin, partner_contact, agent, viewer, IPO member, locked user
- Test every permission rule explicitly

## Database

### Conventions

- `null: false` on columns that are always present
- Boolean columns always `default: false, null: false`
- Status/role columns always `default:` + `null: false`
- Indexes on all foreign keys plus composite indexes on query patterns
- `jsonb` with `default: {}` or `default: []` for flexible attributes

### Seeds

- `find_or_create_by!` for idempotency
- Set `Current.session` during seeding so defaults work
- Realistic data across multiple organisations and countries
- Guard with `unless Rails.env.production?`

## Form Objects

Use `ActiveModel::Model` when an operation spans multiple models:

```ruby
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  # Lives in app/models/, not app/services/
end
```

No service object layer. Keep logic in models. Plain Ruby objects only when genuinely needed.

## Tailwind (HClub-Specific)

Fizzy uses custom CSS, not Tailwind. HClub uses Tailwind v4 with the dark luxury palette defined in `app/assets/tailwind/application.css`. All component styling via utility classes. No custom CSS files unless absolutely necessary.
