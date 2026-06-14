# Task Tracker — Order Payment API

> Rails 8.1 · PostgreSQL · JWT Auth · Midtrans Payment Gateway · Solid Queue/Cache/Cable

---

## Legend

- `[ ]` Not started
- `[/]` In progress
- `[x]` Completed

---

## 1. Database & Migrations

### Schema Overview

| Table                | Key Columns                                                                                             | Status |
|---------------------|---------------------------------------------------------------------------------------------------------|--------|
| `users`              | `email`, `name`, `password_digest`, `otp_code`, `otp_expires_at`, `role`                              | [x]    |
| `products`           | `name`, `description`, `price (decimal 10,2)`, `stock (integer)`, `product_category_id (FK)`          | [x]    |
| `product_categories` | `name (unique)`, `description`, `parent_id (self-ref FK)`                                             | [x]    |
| `orders`             | `user_id`, `total_amount (decimal 12,2)`, `status`                                                    | [x]    |
| `order_items`        | `order_id`, `product_id`, `quantity`, `price (decimal 10,2)`                                          | [x]    |
| `payments`           | `order_id`, `midtrans_transaction_id`, `payment_type`, `gross_amount`, `status`, `raw_response (jsonb)` | [x] |
| `refresh_tokens`     | `user_id`, `token`, `expires_at`, `revoked_at`                                                        | [x]    |

### Tasks

- [x] Migration: `create_users`
  - Columns: `email (NOT NULL, unique index)`, `name`, `otp_code`, `otp_expires_at`, `role (default: "user")`
- [x] Migration: `create_products`
  - Columns: `name (NOT NULL)`, `description`, `price (precision 10, scale 2, NOT NULL)`, `stock (default: 0)`
- [x] Migration: `create_orders`
  - Columns: `user_id (FK)`, `total_amount (precision 12, scale 2)`, `status (default: "pending")`
- [x] Migration: `create_order_items`
  - Columns: `order_id (FK)`, `product_id (FK)`, `quantity (NOT NULL)`, `price (precision 10, scale 2)`
- [x] Migration: `create_payments`
  - Columns: `order_id (FK)`, `midtrans_transaction_id (unique index)`, `payment_type`, `gross_amount`, `status`, `raw_response (jsonb)`
- [x] Migration: `add_password_digest_to_users`
- [x] Migration: `create_refresh_tokens`
  - Columns: `user_id (FK)`, `token (NOT NULL, unique index)`, `expires_at (NOT NULL)`, `revoked_at`
- [x] Migration: `create_product_categories`
  - Columns: `name (NOT NULL, unique index)`, `description`, `parent_id (self-ref FK, index)`
- [x] Migration: `add_category_to_products`
  - Adds: `product_category_id (FK, nullable, index)`
- [ ] Seeds: Complete fixture data for development/testing
  - 1 admin user, 5 regular users
  - 10 products with varied price and stock
  - Sample product categories
  - Sample orders, order_items, payments

---

## 2. Models

### 2.1 User — `app/models/user.rb`

- [x] `has_secure_password` (bcrypt via `password_digest`)
- [x] `has_many :refresh_tokens, dependent: :destroy`
- [ ] `has_many :orders, dependent: :destroy` _(missing from model)_
- [x] Email validation: `presence: true, uniqueness: true, format: URI::MailTo::EMAIL_REGEXP`
- [x] Role enum: `{ user: "user", admin: "admin" }`, default: `"user"`
- [ ] Name validation: `presence: true`
- [ ] Scope `admin` — `where(role: "admin")`
- [ ] Instance method `generate_otp!` — sets `otp_code` (6-digit) and `otp_expires_at` (5 min TTL)
- [ ] Instance method `otp_valid?(code)` — checks code match and expiry

### 2.2 Product — `app/models/product.rb`

- [x] `belongs_to :product_category, optional: true`
- [ ] `has_many :order_items`
- [x] Validation `name`: `presence: true`
- [ ] Validation `name`: `length: { maximum: 255 }` _(not yet added)_
- [x] Validation `price`: `presence: true, numericality: { greater_than: 0 }`
- [x] Validation `stock`: `numericality: { greater_than_or_equal_to: 0, only_integer: true }`
- [x] Scope `in_stock` — `where("stock > 0")`
- [x] Scope `by_category(category_id)` — `where(product_category_id: category_id)`
- [ ] Instance method `in_stock?` — returns `stock > 0`
- [ ] Instance method `decrement_stock!(qty)` — reduces stock, raises `InsufficientStockError` if insufficient

### 2.3 ProductCategory — `app/models/product_category.rb`

- [x] `belongs_to :parent, class_name: "ProductCategory", optional: true` (self-referential)
- [x] `has_many :children, class_name: "ProductCategory", foreign_key: :parent_id, dependent: :nullify`
- [x] `has_many :products, dependent: :nullify`
- [x] Validation `name`: `presence: true, uniqueness: { case_sensitive: false }`
- [x] Validation `description`: `length: { maximum: 1000 }, allow_blank: true`
- [x] Scope `roots` — `where(parent_id: nil)`
- [x] Scope `ordered` — `order(:name)`

### 2.4 Order — `app/models/order.rb`

- [x] `belongs_to :user`
- [ ] `has_many :order_items, dependent: :destroy`
- [ ] `has_one :payment, dependent: :destroy`
- [ ] `accepts_nested_attributes_for :order_items`
- [ ] Status enum: `{ pending: "pending", processing: "processing", completed: "completed", cancelled: "cancelled" }`, default: `"pending"`
- [ ] Callback `before_create :calculate_total` — sums `order_items` subtotals
- [ ] Scope `for_user(user_id)` — filters by user
- [ ] Instance method `cancellable?` — returns `true` only if status is `pending`

### 2.5 OrderItem — `app/models/order_item.rb`

- [x] `belongs_to :order`
- [x] `belongs_to :product`
- [ ] Validation `quantity`: `presence: true, numericality: { greater_than: 0, only_integer: true }`
- [ ] Validation `price`: `presence: true, numericality: { greater_than: 0 }`
- [ ] Instance method `subtotal` — returns `quantity * price`
- [ ] Callback `before_validation :copy_product_price` — snapshots `product.price` at order time

### 2.6 Payment — `app/models/payment.rb`

- [x] `belongs_to :order`
- [ ] Status enum: `{ pending: "pending", paid: "paid", failed: "failed", refunded: "refunded" }`, default: `"pending"`
- [ ] Validation `gross_amount`: `numericality: { greater_than: 0 }`, if present
- [ ] Validation `midtrans_transaction_id`: `uniqueness: true`, allow nil on create
- [ ] Callback `after_update :sync_order_status` — updates `order.status` to `completed` when payment becomes `paid`
- [ ] Instance method `paid?` — returns `status == "paid"`

### 2.7 RefreshToken — `app/models/refresh_token.rb`

- [x] `belongs_to :user`
- [x] Validation `token`: `presence: true, uniqueness: true`
- [x] Validation `expires_at`: `presence: true`
- [x] Scope `active` — `where("expires_at > ? AND revoked_at IS NULL", Time.current)`
- [x] Instance method `revoked?` — returns `revoked_at.present?`
- [x] Instance method `expired?` — returns `expires_at < Time.current`
- [ ] Class method `generate_for(user)` — creates token with `SecureRandom.hex(32)`, TTL 30 days
- [ ] Instance method `revoke!` — sets `revoked_at = Time.current` and saves

---

## 3. Authentication (JWT)

**File locations:**
- `app/controllers/concerns/authenticatable.rb`
- `app/controllers/concerns/authorizable.rb`
- `app/controllers/auth_controller.rb`
- `config/initializers/jwt.rb`

### 3.1 JWT Helper — `config/initializers/jwt.rb`

- [ ] Module `JwtHelper` with:
  - `encode(payload, exp: 24.hours.from_now)` — signs with `Rails.application.secret_key_base`, algorithm `HS256`
  - `decode(token)` — decodes and returns payload hash, raises `JWT::DecodeError` on invalid/expired

### 3.2 Concern: Authenticatable

- [ ] `before_action :authenticate_user!`
- [ ] Reads `Authorization: Bearer <token>` header
- [ ] Decodes JWT, finds `User` by `sub` claim
- [ ] Sets `@current_user`
- [ ] Returns `401 Unauthorized` with `{ error: "Unauthorized" }` on failure

### 3.3 Concern: Authorizable

- [ ] `before_action :require_admin!`
- [ ] Checks `@current_user.admin?`
- [ ] Returns `403 Forbidden` with `{ error: "Forbidden" }` if not admin

### 3.4 Endpoints — `AuthController`

#### POST /api/v1/auth/register

- [ ] **Request body:** `{ email, name, password, password_confirmation }`
- [ ] **Logic:** Create user, return `201` with `{ user: { id, email, name, role } }`
- [ ] **Errors:** `422` with validation messages on failure

#### POST /api/v1/auth/login

- [ ] **Request body:** `{ email, password }`
- [ ] **Logic:**
  1. Find user by email
  2. Authenticate with `authenticate(password)` (has_secure_password)
  3. Generate JWT (`sub: user.id`, exp: 24h)
  4. Create `RefreshToken` (TTL: 30 days)
  5. Return `200` with `{ access_token, refresh_token, token_type: "Bearer", expires_in: 86400 }`
- [ ] **Errors:** `401` with `{ error: "Invalid email or password" }`

#### POST /api/v1/auth/refresh

- [ ] **Request body:** `{ refresh_token }`
- [ ] **Logic:**
  1. Find `RefreshToken` by token string
  2. Validate: not revoked, not expired (use scope `active`)
  3. Revoke old token (`revoke!`)
  4. Issue new JWT + new RefreshToken (token rotation)
  5. Return `200` with `{ access_token, refresh_token, token_type: "Bearer", expires_in: 86400 }`
- [ ] **Errors:** `401` with `{ error: "Invalid or expired refresh token" }`

#### POST /api/v1/auth/logout

- [ ] **Auth:** Requires valid JWT (`authenticate_user!`)
- [ ] **Request body:** `{ refresh_token }`
- [ ] **Logic:** Find and revoke the given refresh token
- [ ] **Response:** `200` with `{ message: "Logged out successfully" }`

---

## 4. Products API

**File locations:**
- `app/controllers/api/v1/products_controller.rb`

All endpoints are under namespace `/api/v1`.

#### GET /api/v1/products

- [ ] **Auth:** None (public)
- [ ] **Query params:** `page`, `per_page` (pagination), `search` (name ILIKE)
- [ ] **Response:** `200` with `{ products: [...], meta: { total, page, per_page } }`
- [ ] **Product fields:** `id, name, description, price, stock, created_at`

#### GET /api/v1/products/:id

- [ ] **Auth:** None (public)
- [ ] **Response:** `200` with full product object
- [ ] **Errors:** `404` with `{ error: "Product not found" }`

#### POST /api/v1/products

- [ ] **Auth:** `authenticate_user!` + `require_admin!`
- [ ] **Request body:** `{ name, description, price, stock }`
- [ ] **Response:** `201` with created product object
- [ ] **Errors:** `422` with validation messages

#### PUT /api/v1/products/:id

- [ ] **Auth:** `authenticate_user!` + `require_admin!`
- [ ] **Request body:** any subset of `{ name, description, price, stock }`
- [ ] **Response:** `200` with updated product object
- [ ] **Errors:** `404`, `422`

#### DELETE /api/v1/products/:id

- [ ] **Auth:** `authenticate_user!` + `require_admin!`
- [ ] **Logic:** Soft-delete or hard-delete (decide based on requirements)
- [ ] **Response:** `204 No Content`
- [ ] **Errors:** `404`

---

## 5. Orders API

**File locations:**
- `app/controllers/api/v1/orders_controller.rb`

#### GET /api/v1/orders

- [ ] **Auth:** `authenticate_user!`
- [ ] **Logic:** Returns only orders belonging to `@current_user`
- [ ] **Response:** `200` with `{ orders: [...] }`
- [ ] **Order fields:** `id, status, total_amount, created_at, order_items: [...]`

#### GET /api/v1/orders/:id

- [ ] **Auth:** `authenticate_user!`
- [ ] **Logic:** Scope to current user; raise `404` if not found or not owned
- [ ] **Response:** `200` with full order including `order_items` and `payment`

#### POST /api/v1/orders

- [ ] **Auth:** `authenticate_user!`
- [ ] **Request body:**
  ```json
  {
    "order": {
      "order_items_attributes": [
        { "product_id": 1, "quantity": 2 },
        { "product_id": 3, "quantity": 1 }
      ]
    }
  }
  ```
- [ ] **Logic:**
  1. Validate all products exist and have sufficient stock
  2. Snapshot `product.price` into `order_item.price`
  3. Calculate `total_amount` from order items
  4. Decrement `product.stock` for each item
  5. Create order with status `pending`
- [ ] **Response:** `201` with created order object
- [ ] **Errors:** `422` on validation failure, `409` if stock insufficient

#### PUT /api/v1/orders/:id/cancel

- [ ] **Auth:** `authenticate_user!`
- [ ] **Logic:**
  1. Find order scoped to current user
  2. Check `cancellable?` (status must be `pending`)
  3. Update status to `cancelled`
  4. Restore `product.stock` for each order item
- [ ] **Response:** `200` with updated order
- [ ] **Errors:** `422` with `{ error: "Order cannot be cancelled" }` if not pending

#### GET /api/v1/admin/orders

- [ ] **Auth:** `authenticate_user!` + `require_admin!`
- [ ] **Query params:** `status`, `user_id`, `page`, `per_page`
- [ ] **Response:** `200` with all orders (paginated)

#### PUT /api/v1/admin/orders/:id/status

- [ ] **Auth:** `authenticate_user!` + `require_admin!`
- [ ] **Request body:** `{ status: "processing" | "completed" | "cancelled" }`
- [ ] **Response:** `200` with updated order
- [ ] **Errors:** `422` on invalid status transition

---

## 6. Payments API (Midtrans Integration)

**File locations:**
- `app/controllers/api/v1/payments_controller.rb`
- `app/services/midtrans_service.rb`

#### POST /api/v1/orders/:order_id/payment

- [ ] **Auth:** `authenticate_user!`
- [ ] **Logic:**
  1. Find order scoped to current user; must be `pending`
  2. Ensure no existing `paid` payment
  3. Call `MidtransService.create_transaction(order)` to get Snap token
  4. Create `Payment` record with status `pending`
  5. Return Snap token for frontend redirect
- [ ] **Response:** `201` with `{ snap_token, redirect_url, payment: { id, status } }`
- [ ] **Errors:** `422` if order not in correct state

#### GET /api/v1/orders/:order_id/payment

- [ ] **Auth:** `authenticate_user!`
- [ ] **Response:** `200` with `{ id, status, payment_type, gross_amount, midtrans_transaction_id }`
- [ ] **Errors:** `404` if payment not found

#### POST /api/v1/payments/webhook

- [ ] **Auth:** None (Midtrans server-to-server); validate `signature_key`
- [ ] **Signature validation:** `SHA512(order_id + status_code + gross_amount + server_key)`
- [ ] **Logic:**
  1. Parse Midtrans notification body
  2. Validate signature
  3. Find `Payment` by `midtrans_transaction_id`
  4. Map Midtrans status → internal status:
     - `settlement` → `paid` → trigger `order.completed`
     - `deny` / `cancel` / `expire` → `failed`
     - `refund` → `refunded`
  5. Update `Payment` status and `raw_response`
- [ ] **Response:** `200 OK` (Midtrans expects 200 regardless)

### 6.1 MidtransService — `app/services/midtrans_service.rb`

- [ ] `create_transaction(order)` — calls Midtrans Snap API, returns `{ snap_token, redirect_url }`
- [ ] `verify_signature(notification)` — validates webhook signature
- [ ] Configuration via credentials: `midtrans.server_key`, `midtrans.client_key`, `midtrans.production` (bool)

---

## 7. Routes — `config/routes.rb`

- [x] Health check: `GET /up`
- [ ] Namespace `api`, `v1` — **routes not yet defined**, only health check exists:
  ```ruby
  namespace :api do
    namespace :v1 do
      # Auth
      post "auth/register",  to: "auth#register"
      post "auth/login",     to: "auth#login"
      post "auth/refresh",   to: "auth#refresh"
      post "auth/logout",    to: "auth#logout"

      # Products
      resources :products, only: [:index, :show, :create, :update, :destroy]

      # Product Categories
      resources :product_categories, only: [:index, :show, :create, :update, :destroy]

      # Orders
      resources :orders, only: [:index, :show, :create] do
        member do
          put :cancel
        end
        resource :payment, only: [:create, :show], controller: "payments"
      end

      # Admin
      namespace :admin do
        resources :orders, only: [:index] do
          member do
            put :status
          end
        end
      end

      # Webhook
      post "payments/webhook", to: "payments#webhook"
    end
  end
  ```


  ```ruby
  namespace :api do
    namespace :v1 do
      # Auth
      post "auth/register",  to: "auth#register"
      post "auth/login",     to: "auth#login"
      post "auth/refresh",   to: "auth#refresh"
      post "auth/logout",    to: "auth#logout"

      # Products
      resources :products, only: [:index, :show, :create, :update, :destroy]

      # Orders
      resources :orders, only: [:index, :show, :create] do
        member do
          put :cancel
        end
        resource :payment, only: [:create, :show], controller: "payments"
      end

      # Admin
      namespace :admin do
        resources :orders, only: [:index] do
          member do
            put :status
          end
        end
      end

      # Webhook
      post "payments/webhook", to: "payments#webhook"
    end
  end
  ```

---

## 8. Testing

### 8.1 Model Tests

| File | Cases to cover |
|------|---------------|
| `user_test.rb` | Valid user creation, email uniqueness, email format, role enum, `has_secure_password` |
| `product_test.rb` | Name/price presence, price > 0, stock >= 0, `in_stock?`, `decrement_stock!`, category association |
| `product_category_test.rb` | Name uniqueness, parent/children hierarchy, `roots` scope |
| `order_test.rb` | Associations, status enum, `cancellable?`, total calculation |
| `order_item_test.rb` | Associations, quantity > 0, `subtotal`, price snapshot callback |
| `payment_test.rb` | Associations, status enum, `paid?`, signature validation |
| `refresh_token_test.rb` | `revoked?`, `expired?`, `active` scope, `revoke!`, `generate_for` |


### 8.2 Controller / Integration Tests

| Feature | Test cases |
|---------|-----------|
| Register | Success 201, duplicate email 422, missing fields 422 |
| Login | Success 200 + tokens, wrong password 401, unknown email 401 |
| Refresh | Success 200 with new tokens, expired token 401, revoked token 401 |
| Logout | Success 200, invalid token 401 |
| Products | CRUD happy paths, admin-only enforcement 403, 404 not found |
| Orders | Create with valid items, stock check failure, cancel, admin list |
| Payments | Initiate payment, webhook settlement, webhook invalid signature |

---

## 9. Infrastructure & Config

- [x] `Gemfile`: `jwt` gem added
- [x] `Gemfile`: `pg` (PostgreSQL adapter)
- [x] `Gemfile`: `rails ~> 8.1.3`
- [x] Solid Queue, Solid Cache, Solid Cable configured
- [x] `docker-compose.yml` — `db` (PostgreSQL 16) + `redis` (7) services only; no `web` service
- [x] `Dockerfile` — container build config
- [x] Kamal deploy config (`config/deploy.yml`)
- [x] `config/initializers/cors.rb` — file exists, middleware **commented out**
- [ ] Uncomment and configure `rack-cors` middleware in `config/initializers/cors.rb`
  - Add `gem "rack-cors"` to `Gemfile`
  - Allow `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`
  - Set allowed origins per environment
- [ ] `config/initializers/jwt.rb` — `JwtHelper` module — **file not yet created**
- [ ] `config/credentials.yml.enc` — add `midtrans.server_key`, `midtrans.client_key` — **not yet set**
- [ ] Uncomment `gem "bcrypt"` in `Gemfile` — required by `has_secure_password`
- [ ] `app/controllers/concerns/authenticatable.rb` — **not yet created**
- [ ] `app/controllers/concerns/authorizable.rb` — **not yet created**
- [ ] `app/controllers/concerns/paginatable.rb` — **not yet created**
- [ ] `app/errors/` directory — custom error classes — **not yet created**
- [ ] `app/services/midtrans_service.rb` — **not yet created**


---

## 10. CI/CD (GitHub Actions)

**File:** `.github/workflows/ci.yml`

- [ ] Trigger: `push` and `pull_request` to `main`
- [ ] Jobs:
  - [ ] `test` — Setup PostgreSQL service, run `rails db:create db:migrate`, run `rails test`
  - [ ] `security` — Run `brakeman --no-pager` and `bundler-audit`
  - [ ] `lint` — Run `rubocop`
- [ ] Environment variables in CI: `RAILS_ENV=test`, `DATABASE_URL`, `RAILS_MASTER_KEY`

---

## 11. Documentation

- [x] `README.md` (basic scaffold)
- [ ] Update `README.md`:
  - Project overview
  - Prerequisites (Ruby version, PostgreSQL, etc.)
  - Setup instructions (`bundle install`, `rails db:setup`)
  - Environment variables reference
  - How to run tests
- [ ] `doc/api.md` or OpenAPI spec (`doc/openapi.yml`):
  - All endpoints with request/response examples
  - Authentication flow diagram
  - Error codes reference table

---

## 12. Pagination

> Implementasi pagination manual (tanpa gem Kaminari/Pagy) menggunakan query `limit` & `offset` di ActiveRecord.

### 12.1 Setup — Concern Paginatable

**File:** `app/controllers/concerns/paginatable.rb`

- [ ] Buat module `Paginatable` sebagai `ActiveSupport::Concern`
- [ ] Method `paginate(scope)` — menerima ActiveRecord scope, menerapkan `limit` & `offset`
- [ ] Method `pagination_meta(scope)` — mengembalikan hash meta untuk response:
  ```json
  {
    "current_page": 1,
    "per_page": 10,
    "total_count": 100,
    "total_pages": 10
  }
  ```
- [ ] Helper method `current_page` — ambil dari `params[:page]`, default `1`, minimum `1`
- [ ] Helper method `per_page` — ambil dari `params[:per_page]`, default `10`, maksimum `100`

### 12.2 Implementasi per Endpoint

#### GET /api/v1/products (index)

- [ ] Include `Paginatable` di `ProductsController`
- [ ] Terapkan `paginate(@products)` sebelum render
- [ ] Response format:
  ```json
  {
    "products": [...],
    "meta": {
      "current_page": 1,
      "per_page": 10,
      "total_count": 50,
      "total_pages": 5
    }
  }
  ```
- [ ] Query params: `?page=1&per_page=10`

#### GET /api/v1/orders (index — user)

- [ ] Include `Paginatable` di `OrdersController`
- [ ] Terapkan `paginate` pada scope orders milik `@current_user`
- [ ] Response format:
  ```json
  {
    "orders": [...],
    "meta": {
      "current_page": 1,
      "per_page": 10,
      "total_count": 20,
      "total_pages": 2
    }
  }
  ```

#### GET /api/v1/admin/orders (index — admin)

- [ ] Include `Paginatable` di `Admin::OrdersController`
- [ ] Query params: `?page=1&per_page=20&status=pending&user_id=5`
- [ ] Response format sama dengan orders user

### 12.3 Contoh Implementasi Concern

```ruby
# app/controllers/concerns/paginatable.rb
module Paginatable
  extend ActiveSupport::Concern

  DEFAULT_PAGE     = 1
  DEFAULT_PER_PAGE = 10
  MAX_PER_PAGE     = 100

  def paginate(scope)
    scope.limit(per_page).offset((current_page - 1) * per_page)
  end

  def pagination_meta(scope)
    total_count = scope.except(:limit, :offset).count
    {
      current_page: current_page,
      per_page:     per_page,
      total_count:  total_count,
      total_pages:  (total_count.to_f / per_page).ceil
    }
  end

  private

  def current_page
    [params[:page].to_i, DEFAULT_PAGE].max
  end

  def per_page
    requested = params[:per_page].to_i
    requested.between?(1, MAX_PER_PAGE) ? requested : DEFAULT_PER_PAGE
  end
end
```

### 12.4 Testing Pagination

**File:** `test/controllers/api/v1/products_controller_test.rb`

- [ ] Test default pagination (page=1, per_page=10)
- [ ] Test custom `per_page` (e.g., 5)
- [ ] Test `page` out of range → return empty array dengan meta yang benar
- [ ] Test `per_page` melebihi MAX → clamp ke 100
- [ ] Verifikasi format meta response (`current_page`, `per_page`, `total_count`, `total_pages`)

---

## 13. API Documentation (Swagger / OpenAPI)

> Interactive API documentation using `rswag` (Swagger UI + RSpec DSL). Generates an OpenAPI 3.0 spec from RSpec request specs and serves it via a built-in Swagger UI.

### 13.1 Dependencies

**File:** `Gemfile`

- [ ] Add `rswag-api` — serves the generated OpenAPI JSON spec
- [ ] Add `rswag-ui` — mounts Swagger UI at `/api-docs`
- [ ] Add `rswag-specs` to `group :development, :test` — RSpec DSL for writing specs

```ruby
gem "rswag-api"
gem "rswag-ui"

group :development, :test do
  gem "rswag-specs"
end
```

### 13.2 Installation

- [ ] Run the rswag installer:

```bash
rails generate rswag:install
```

This generates:
- `config/initializers/rswag_api.rb`
- `config/initializers/rswag_ui.rb`
- `spec/swagger_helper.rb`
- Mounts `/api-docs` route automatically

- [ ] Mount Swagger UI in `config/routes.rb`:

```ruby
mount Rswag::Ui::Engine => "/api-docs"
mount Rswag::Api::Engine => "/api-docs"
```

### 13.3 Swagger Configuration

**File:** `spec/swagger_helper.rb`

- [ ] Define OpenAPI metadata:

```ruby
RSpec.configure do |config|
  config.swagger_root = Rails.root.join("swagger").to_s

  config.swagger_docs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Order Payment API",
        version: "v1",
        description: "REST API for order and payment management"
      },
      servers: [
        { url: "http://localhost:3000", description: "Development" }
      ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: "JWT"
          }
        }
      },
      security: [{ bearerAuth: [] }]
    }
  }

  config.swagger_format = :yaml
end
```

### 13.4 Writing Swagger Specs

All Swagger specs live in `spec/requests/api/v1/`.

#### Auth — `spec/requests/api/v1/auth_spec.rb`

- [ ] `POST /api/v1/auth/register` — document request body & 201/422 responses
- [ ] `POST /api/v1/auth/login` — document tokens in response & 200/401 responses
- [ ] `POST /api/v1/auth/refresh` — document token rotation & 200/401 responses
- [ ] `POST /api/v1/auth/logout` — document 200 response

#### Products — `spec/requests/api/v1/products_spec.rb`

- [ ] `GET /api/v1/products` — include `page`, `per_page`, `search` query params; document paginated response
- [ ] `GET /api/v1/products/{id}` — document 200 & 404 responses
- [ ] `POST /api/v1/products` — document request body, 201 & 422 responses, `bearerAuth` security
- [ ] `PUT /api/v1/products/{id}` — document 200, 404 & 422 responses
- [ ] `DELETE /api/v1/products/{id}` — document 204 & 404 responses

#### Orders — `spec/requests/api/v1/orders_spec.rb`

- [ ] `GET /api/v1/orders` — document paginated response
- [ ] `GET /api/v1/orders/{id}` — document full order with items & payment
- [ ] `POST /api/v1/orders` — document nested `order_items_attributes`
- [ ] `PUT /api/v1/orders/{id}/cancel` — document 200 & 422 responses

#### Payments — `spec/requests/api/v1/payments_spec.rb`

- [ ] `POST /api/v1/orders/{order_id}/payment` — document Snap token response
- [ ] `GET /api/v1/orders/{order_id}/payment` — document payment status response
- [ ] `POST /api/v1/payments/webhook` — document signature validation & 200 response (no auth)

#### Admin Orders — `spec/requests/api/v1/admin/orders_spec.rb`

- [ ] `GET /api/v1/admin/orders` — document `status`, `user_id`, `page`, `per_page` query params
- [ ] `PUT /api/v1/admin/orders/{id}/status` — document status transition body & responses

### 13.5 Example Spec Structure

```ruby
# spec/requests/api/v1/products_spec.rb
require "swagger_helper"

RSpec.describe "Products API", type: :request do
  path "/api/v1/products" do
    get "Returns a paginated list of products" do
      tags "Products"
      produces "application/json"
      parameter name: :page,     in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false
      parameter name: :search,   in: :query, type: :string,  required: false

      response "200", "Products retrieved successfully" do
        schema type: :object,
          properties: {
            products: { type: :array, items: { "$ref" => "#/components/schemas/Product" } },
            meta: { "$ref" => "#/components/schemas/PaginationMeta" }
          }
        run_test!
      end
    end

    post "Creates a product (admin only)" do
      tags "Products"
      security [{ bearerAuth: [] }]
      consumes "application/json"
      produces "application/json"
      parameter name: :product, in: :body, schema: {
        type: :object,
        properties: {
          name:        { type: :string },
          description: { type: :string },
          price:       { type: :number },
          stock:       { type: :integer }
        },
        required: %w[name price stock]
      }

      response "201", "Product created" do run_test! end
      response "422", "Validation failed" do run_test! end
      response "403", "Forbidden" do run_test! end
    end
  end
end
```

### 13.6 Reusable Schema Components

**File:** `spec/swagger_helper.rb` — define under `components.schemas`:

- [ ] `Product` — `id`, `name`, `description`, `price`, `stock`, `created_at`
- [ ] `Order` — `id`, `status`, `total_amount`, `created_at`, `order_items`
- [ ] `OrderItem` — `id`, `product_id`, `quantity`, `price`
- [ ] `Payment` — `id`, `status`, `payment_type`, `gross_amount`, `midtrans_transaction_id`
- [ ] `PaginationMeta` — `current_page`, `per_page`, `total_count`, `total_pages`
- [ ] `ErrorResponse` — `error` (string)
- [ ] `ValidationError` — `errors` (object with field arrays)

### 13.7 Generating the Spec File

- [ ] Run the following command to generate `swagger/v1/swagger.yaml`:

```bash
RAILS_ENV=test rails rswag:specs:swaggerize
```

- [ ] Add this command to the CI pipeline (after `rails test`)
- [ ] Commit the generated `swagger/v1/swagger.yaml` to version control

### 13.8 Accessing Swagger UI

Once the server is running, the interactive documentation is available at:

```
http://localhost:3000/api-docs
```

For Docker:

```bash
docker compose exec web rails rswag:specs:swaggerize
```

Then open `http://localhost:3000/api-docs` in a browser.

---

## 14. Error Handling

> Centralized error handling via `ApplicationController` using `rescue_from`. All errors return a consistent JSON structure.

### 14.1 Standard Error Response Format

All error responses follow this structure:

```json
{
  "error": "Human-readable message"
}
```

Validation errors use an extended format:

```json
{
  "errors": {
    "field_name": ["can't be blank", "is too short"]
  }
}
```

### 14.2 Global Error Handlers — `app/controllers/application_controller.rb`

- [ ] `rescue_from ActiveRecord::RecordNotFound` → `404 Not Found`

```ruby
rescue_from ActiveRecord::RecordNotFound do |e|
  render json: { error: e.message }, status: :not_found
end
```

- [ ] `rescue_from ActiveRecord::RecordInvalid` → `422 Unprocessable Entity`

```ruby
rescue_from ActiveRecord::RecordInvalid do |e|
  render json: { errors: e.record.errors }, status: :unprocessable_entity
end
```

- [ ] `rescue_from ActionController::ParameterMissing` → `400 Bad Request`

```ruby
rescue_from ActionController::ParameterMissing do |e|
  render json: { error: e.message }, status: :bad_request
end
```

- [ ] `rescue_from JWT::DecodeError` → `401 Unauthorized`

```ruby
rescue_from JWT::DecodeError do
  render json: { error: "Invalid or expired token" }, status: :unauthorized
end
```

- [ ] `rescue_from JWT::ExpiredSignature` → `401 Unauthorized`

```ruby
rescue_from JWT::ExpiredSignature do
  render json: { error: "Token has expired" }, status: :unauthorized
end
```

- [ ] `rescue_from StandardError` (catch-all, development only) → `500 Internal Server Error`

```ruby
rescue_from StandardError do |e|
  render json: { error: "Internal server error" }, status: :internal_server_error
end
```

### 14.3 HTTP Status Code Reference

| Status Code | Constant | When to use |
|---|---|---|
| `200` | `:ok` | Successful GET, PUT |
| `201` | `:created` | Resource successfully created (POST) |
| `204` | `:no_content` | Successful DELETE (no body) |
| `400` | `:bad_request` | Missing required parameter, malformed request body |
| `401` | `:unauthorized` | Missing, invalid, or expired JWT token |
| `403` | `:forbidden` | Authenticated but not authorized (e.g., non-admin accessing admin routes) |
| `404` | `:not_found` | Record does not exist or is not accessible to the current user |
| `409` | `:conflict` | Business logic conflict (e.g., insufficient stock, duplicate payment) |
| `422` | `:unprocessable_entity` | Validation errors on create/update |
| `500` | `:internal_server_error` | Unexpected server error |

### 14.4 Domain-Specific Errors to Handle

#### Authentication & Authorization

- [ ] No `Authorization` header present → `401` with `{ "error": "Authorization header is missing" }`
- [ ] Token format invalid (not `Bearer <token>`) → `401` with `{ "error": "Invalid authorization format" }`
- [ ] JWT signature invalid → `401` with `{ "error": "Invalid or expired token" }`
- [ ] JWT expired (`JWT::ExpiredSignature`) → `401` with `{ "error": "Token has expired" }`
- [ ] User not found from JWT `sub` claim → `401` with `{ "error": "Unauthorized" }`
- [ ] Non-admin accessing admin endpoint → `403` with `{ "error": "Forbidden" }`

#### Authentication Endpoints

- [ ] `POST /auth/login` — wrong password or email not found → `401` with `{ "error": "Invalid email or password" }`
- [ ] `POST /auth/refresh` — token not found → `401` with `{ "error": "Invalid or expired refresh token" }`
- [ ] `POST /auth/refresh` — token revoked → `401` with `{ "error": "Invalid or expired refresh token" }`
- [ ] `POST /auth/refresh` — token expired → `401` with `{ "error": "Invalid or expired refresh token" }`
- [ ] `POST /auth/register` — duplicate email → `422` with validation errors

#### Products

- [ ] `GET/PUT/DELETE /products/:id` — product not found → `404` with `{ "error": "Product not found" }`
- [ ] `POST/PUT /products` — validation failure (blank name, price <= 0) → `422` with field errors
- [ ] `POST/PUT /products` — non-admin user → `403` with `{ "error": "Forbidden" }`

#### Orders

- [ ] `GET/PUT /orders/:id` — order not found or does not belong to current user → `404` with `{ "error": "Order not found" }`
- [ ] `POST /orders` — product not found in order items → `404` with `{ "error": "Product not found" }`
- [ ] `POST /orders` — insufficient stock → `409` with `{ "error": "Insufficient stock for product: <name>" }`
- [ ] `POST /orders` — empty `order_items_attributes` → `422` with `{ "error": "Order must have at least one item" }`
- [ ] `PUT /orders/:id/cancel` — order is not in `pending` state → `422` with `{ "error": "Order cannot be cancelled" }`

#### Payments

- [ ] `POST /orders/:order_id/payment` — order not found or not owned → `404` with `{ "error": "Order not found" }`
- [ ] `POST /orders/:order_id/payment` — order is not in `pending` state → `422` with `{ "error": "Payment can only be initiated for pending orders" }`
- [ ] `POST /orders/:order_id/payment` — existing `paid` payment → `409` with `{ "error": "Order has already been paid" }`
- [ ] `POST /payments/webhook` — signature validation failure → `401` with `{ "error": "Invalid webhook signature" }`
- [ ] `POST /payments/webhook` — payment record not found by transaction ID → `404` (log silently, return `200` to Midtrans)

#### Admin Orders

- [ ] `PUT /admin/orders/:id/status` — invalid status value → `422` with `{ "error": "Invalid status transition" }`
- [ ] `PUT /admin/orders/:id/status` — order not found → `404` with `{ "error": "Order not found" }`

### 14.5 Custom Error Classes (Optional)

For business logic errors, define custom exception classes in `app/errors/`:

- [ ] `app/errors/insufficient_stock_error.rb` — raised when `product.stock < requested quantity`
- [ ] `app/errors/invalid_order_state_error.rb` — raised on invalid order state transitions
- [ ] `app/errors/invalid_webhook_signature_error.rb` — raised when Midtrans signature is invalid
- [ ] Register each with `rescue_from` in `ApplicationController` with the appropriate status code

```ruby
# app/errors/insufficient_stock_error.rb
class InsufficientStockError < StandardError; end

# app/controllers/application_controller.rb
rescue_from InsufficientStockError do |e|
  render json: { error: e.message }, status: :conflict
end
```

### 14.6 Testing Error Handling

- [ ] Test each `rescue_from` handler in `test/controllers/application_controller_test.rb`
- [ ] Test `404` — request a non-existent record ID
- [ ] Test `401` — request without a token, with an expired token, and with a malformed token
- [ ] Test `403` — regular user accessing an admin-only endpoint
- [ ] Test `422` — submit invalid params for create/update endpoints
- [ ] Test `409` — attempt to create an order with insufficient stock
- [ ] Test webhook with an invalid signature → verify `401` response
