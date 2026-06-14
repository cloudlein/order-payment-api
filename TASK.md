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

| Table           | Key Columns                                                                 | Status |
|----------------|-----------------------------------------------------------------------------|--------|
| `users`         | `email`, `name`, `password_digest`, `otp_code`, `otp_expires_at`, `role`  | [x]    |
| `products`      | `name`, `description`, `price (decimal 10,2)`, `stock (integer)`           | [x]    |
| `orders`        | `user_id`, `total_amount (decimal 12,2)`, `status`                         | [x]    |
| `order_items`   | `order_id`, `product_id`, `quantity`, `price (decimal 10,2)`               | [x]    |
| `payments`      | `order_id`, `midtrans_transaction_id`, `payment_type`, `gross_amount`, `status`, `raw_response (jsonb)` | [x] |
| `refresh_tokens`| `user_id`, `token`, `expires_at`, `revoked_at`                             | [x]    |

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
- [ ] Seeds: Complete fixture data for development/testing
  - 1 admin user, 5 regular users
  - 10 products with varied price and stock
  - Sample orders, order_items, payments

---

## 2. Models

### 2.1 User — `app/models/user.rb`

- [x] `has_secure_password` (bcrypt via `password_digest`)
- [x] `has_many :refresh_tokens, dependent: :destroy`
- [x] `has_many :orders, dependent: :destroy`
- [x] Email validation: `presence: true, uniqueness: true, format: URI::MailTo::EMAIL_REGEXP`
- [x] Role enum: `{ user: "user", admin: "admin" }`, default: `"user"`
- [ ] Name validation: `presence: true`
- [ ] Scope `admin` — `where(role: "admin")`
- [ ] Instance method `generate_otp!` — sets `otp_code` (6-digit) and `otp_expires_at` (5 min TTL)
- [ ] Instance method `otp_valid?(code)` — checks code match and expiry

### 2.2 Product — `app/models/product.rb`

- [x] Base model created
- [ ] `has_many :order_items`
- [ ] Validations:
  - `name`: `presence: true, length: { maximum: 255 }`
  - `price`: `presence: true, numericality: { greater_than: 0 }`
  - `stock`: `numericality: { greater_than_or_equal_to: 0 }`
- [ ] Scope `available` — `where("stock > 0")`
- [ ] Instance method `in_stock?` — returns `stock > 0`
- [ ] Instance method `decrement_stock!(qty)` — reduces stock, raises error if insufficient

### 2.3 Order — `app/models/order.rb`

- [x] `belongs_to :user`
- [ ] `has_many :order_items, dependent: :destroy`
- [ ] `has_one :payment, dependent: :destroy`
- [ ] `accepts_nested_attributes_for :order_items`
- [ ] Status enum: `{ pending: "pending", processing: "processing", completed: "completed", cancelled: "cancelled" }`, default: `"pending"`
- [ ] Callback `before_create :calculate_total` — sums `order_items` subtotals
- [ ] Scope `for_user(user_id)` — filters by user
- [ ] Instance method `cancellable?` — returns `true` only if status is `pending`

### 2.4 OrderItem — `app/models/order_item.rb`

- [x] `belongs_to :order`
- [x] `belongs_to :product`
- [ ] Validation `quantity`: `presence: true, numericality: { greater_than: 0, only_integer: true }`
- [ ] Validation `price`: `presence: true, numericality: { greater_than: 0 }`
- [ ] Instance method `subtotal` — returns `quantity * price`
- [ ] Callback `before_validation :copy_product_price` — snapshots `product.price` at order time

### 2.5 Payment — `app/models/payment.rb`

- [x] `belongs_to :order`
- [ ] Status enum: `{ pending: "pending", paid: "paid", failed: "failed", refunded: "refunded" }`, default: `"pending"`
- [ ] Validation `gross_amount`: `numericality: { greater_than: 0 }`, if present
- [ ] Validation `midtrans_transaction_id`: `uniqueness: true`, allow nil on create
- [ ] Callback `after_update :sync_order_status` — updates `order.status` to `completed` when payment becomes `paid`
- [ ] Instance method `paid?` — returns `status == "paid"`

### 2.6 RefreshToken — `app/models/refresh_token.rb`

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
- [ ] Namespace `api`, `v1`:
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
| `user_test.rb` | Valid user creation, email uniqueness, email format, role enum, has_secure_password |
| `product_test.rb` | Name/price presence, price > 0, stock >= 0, `in_stock?`, `decrement_stock!` |
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
- [x] Solid Queue, Solid Cache, Solid Cable configured
- [x] Docker / Dockerfile
- [x] Kamal deploy config (`config/deploy.yml`)
- [ ] `rack-cors` — add to Gemfile and create `config/initializers/cors.rb`
  - Allow `GET`, `POST`, `PUT`, `DELETE`, `OPTIONS`
  - Origins: configure per environment
- [ ] `config/initializers/jwt.rb` — `JwtHelper` module (encode/decode)
- [ ] `config/credentials.yml.enc` — add `midtrans.server_key`, `midtrans.client_key`
- [ ] Add `bcrypt` gem (required by `has_secure_password`)

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
