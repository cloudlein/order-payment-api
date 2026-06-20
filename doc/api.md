# Order Payment API Reference

This document serves as the complete technical API Reference for the Order Payment API.

---

## 1. Global Specifications

### Base URL
* **Development:** `http://localhost:3000`
* **Production:** `https://api.yourdomain.com` (configured via deploy environment)

### Headers
All write requests (`POST`, `PUT`, `PATCH`, `DELETE`) require the `Content-Type` header.
```http
Content-Type: application/json
Accept: application/json
```

For authenticated endpoints, include the JWT Access Token in the `Authorization` header:
```http
Authorization: Bearer <your_access_token>
```

---

## 2. Global Error Responses & Custom Codes

All error responses return a standardized JSON structure.

### Standard Error Format
```json
{
  "error": "Human-readable explanation of what went wrong"
}
```

### Validation Error Format (`422 Unprocessable Entity`)
```json
{
  "errors": {
    "email": ["can't be blank", "is invalid"],
    "password": ["is too short (minimum is 6 characters)"]
  }
}
```

### Error Code Reference Table
| HTTP Status | Custom Code | Description |
| :--- | :--- | :--- |
| `400 Bad Request` | - | Missing required parameter or malformed request body. |
| `401 Unauthorized` | `UNAUTHORIZED` / `INVALID_WEBHOOK_SIGNATURE` | Missing/expired JWT access token, or invalid signature on webhook. |
| `403 Forbidden` | `FORBIDDEN` | Authenticated user lacks permission (non-admin accessing admin resources). |
| `404 Not Found` | - | Requested resource (Product, Order, etc.) does not exist or is not owned. |
| `409 Conflict` | `INSUFFICIENT_STOCK` / `PAYMENT_ALREADY_PAID` | Stock unavailable or order is already paid. |
| `422 Unprocessable Entity`| `INVALID_ORDER_STATE` | Validation errors or invalid transition (e.g. cancelling a processed order). |

---

## 3. Pagination Protocol

For all `GET` index endpoints that support pagination, the following query parameters are accepted:
* `page` (integer, default: `1`): The page offset.
* `per_page` (integer, default: `10`, maximum: `100`): Items per page.

### Paginated Meta Object
All paginated endpoints enclose the list of resources under a key corresponding to the resource name, alongside a `meta` block:
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

---

## 4. Endpoints Documentation

### 4.1 Authentication Service (`/api/v1/auth`)

#### Register a New User
* **Method & Path:** `POST /api/v1/auth/register`
* **Authentication:** None (Public)
* **Request Body:**
  ```json
  {
    "user": {
      "email": "user@example.com",
      "name": "John Doe",
      "password": "securepassword123",
      "password_confirmation": "securepassword123"
    }
  }
  ```
* **Success Response (`201 Created`):**
  ```json
  {
    "user": {
      "id": 5,
      "email": "user@example.com",
      "name": "John Doe",
      "role": "user"
    }
  }
  ```
* **Errors:** `422 Unprocessable Entity` (if email exists or validation fails).

#### User Login
* **Method & Path:** `POST /api/v1/auth/login`
* **Authentication:** None (Public)
* **Request Body:**
  ```json
  {
    "email": "user@example.com",
    "password": "securepassword123"
  }
  ```
* **Success Response (`200 OK`):**
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiJ9...",
    "refresh_token": "8f2a632db2f90a9b...",
    "token_type": "Bearer",
    "expires_in": 86400
  }
  ```
* **Errors:** `401 Unauthorized` with `{ "error": "Invalid email or password" }`.

#### Token Refresh Rotation
* **Method & Path:** `POST /api/v1/auth/refresh`
* **Authentication:** None (Public)
* **Request Body:**
  ```json
  {
    "refresh_token": "8f2a632db2f90a9b..."
  }
  ```
* **Success Response (`200 OK`):** Returns rotated access and refresh tokens:
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiJ9_new...",
    "refresh_token": "f3b9c03b12ea7483_new...",
    "token_type": "Bearer",
    "expires_in": 86400
  }
  ```
* **Errors:** `401 Unauthorized` with `{ "error": "Invalid or expired refresh token" }`.

#### Logout
* **Method & Path:** `POST /api/v1/auth/logout`
* **Authentication:** JWT Access Token required
* **Request Body:**
  ```json
  {
    "refresh_token": "f3b9c03b12ea7483_new..."
  }
  ```
* **Success Response (`200 OK`):**
  ```json
  {
    "message": "Logged out successfully"
  }
  ```

---

### 4.2 Products Catalog Service (`/api/v1/products`)

#### List Products (Paginated & Searchable)
* **Method & Path:** `GET /api/v1/products`
* **Authentication:** None (Public)
* **Query Parameters:** `page`, `per_page`, `search` (filters by name)
* **Success Response (`200 OK`):**
  ```json
  {
    "products": [
      {
        "id": 1,
        "name": "High Performance Gaming Laptop",
        "description": "Powerful gaming laptop with 32GB RAM",
        "price": "1500.00",
        "stock": 14,
        "created_at": "2026-06-20T12:00:00.000Z"
      }
    ],
    "meta": {
      "current_page": 1,
      "per_page": 10,
      "total_count": 1,
      "total_pages": 1
    }
  }
  ```

#### Get Specific Product
* **Method & Path:** `GET /api/v1/products/:id`
* **Authentication:** None (Public)
* **Success Response (`200 OK`):**
  ```json
  {
    "id": 1,
    "name": "High Performance Gaming Laptop",
    "description": "Powerful gaming laptop with 32GB RAM",
    "price": "1500.00",
    "stock": 14,
    "created_at": "2026-06-20T12:00:00.000Z"
  }
  ```
* **Errors:** `404 Not Found` if the product doesn't exist.

#### Create Product (Admin Only)
* **Method & Path:** `POST /api/v1/products`
* **Authentication:** JWT (Admin Only)
* **Request Body:**
  ```json
  {
    "product": {
      "name": "Mechanical Keyboard",
      "description": "Brown switches mechanical keyboard",
      "price": 89.99,
      "stock": 50
    }
  }
  ```
* **Success Response (`201 Created`):** Returns the created product object.
* **Errors:** `403 Forbidden` (if not admin), `422 Unprocessable Entity` (if validations fail).

#### Update Product (Admin Only)
* **Method & Path:** `PUT /api/v1/products/:id`
* **Authentication:** JWT (Admin Only)
* **Request Body:** Any subset of fields (e.g. update stock only):
  ```json
  {
    "product": {
      "stock": 45
    }
  }
  ```
* **Success Response (`200 OK`):** Returns the updated product.

#### Delete Product (Admin Only)
* **Method & Path:** `DELETE /api/v1/products/:id`
* **Authentication:** JWT (Admin Only)
* **Success Response (`204 No Content`):** Empty body.

---

### 4.3 Orders Service (`/api/v1/orders`)

#### List User Orders
* **Method & Path:** `GET /api/v1/orders`
* **Authentication:** JWT Required
* **Success Response (`200 OK`):**
  ```json
  {
    "orders": [
      {
        "id": 12,
        "status": "pending",
        "total_amount": "3089.99",
        "created_at": "2026-06-20T15:00:00.000Z",
        "order_items": [
          {
            "id": 20,
            "product_id": 1,
            "quantity": 2,
            "price": "1500.00"
          },
          {
            "id": 21,
            "product_id": 4,
            "quantity": 1,
            "price": "89.99"
          }
        ]
      }
    ]
  }
  ```

#### Get Specific Order
* **Method & Path:** `GET /api/v1/orders/:id`
* **Authentication:** JWT Required (scoped to current user unless Admin)
* **Success Response (`200 OK`):** Returns the order detail, including items and payment details if any.

#### Create Order
* **Method & Path:** `POST /api/v1/orders`
* **Authentication:** JWT Required
* **Request Body:**
  ```json
  {
    "order": {
      "order_items_attributes": [
        { "product_id": 1, "quantity": 2 },
        { "product_id": 4, "quantity": 1 }
      ]
    }
  }
  ```
* **Success Response (`201 Created`):** Returns the created order.
* **Errors:**
  * `409 Conflict` with `{ "error": "Insufficient stock for product: <name>" }`
  * `422 Unprocessable Entity` if `order_items_attributes` is empty.

#### Cancel Order
* **Method & Path:** `PUT /api/v1/orders/:id/cancel`
* **Authentication:** JWT Required (scoped to current user)
* **Success Response (`200 OK`):** Returns updated order with status `"cancelled"`.
* **Errors:**
  * `422 Unprocessable Entity` with `{ "error": "Order cannot be cancelled" }` (if order status is not `pending`).

---

### 4.4 Payment Service (`/api/v1/orders/:order_id/payment`)

#### Initiate Payment
* **Method & Path:** `POST /api/v1/orders/:order_id/payment`
* **Authentication:** JWT Required (scoped to owner of order)
* **Success Response (`201 Created`):**
  ```json
  {
    "snap_token": "a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "redirect_url": "https://app.sandbox.midtrans.com/snap/v2/vtweb/a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d",
    "payment": {
      "id": 8,
      "status": "pending"
    }
  }
  ```
* **Errors:**
  * `409 Conflict` with `{ "error": "Order has already been paid" }`
  * `422 Unprocessable Entity` if order status is not `pending`.

#### Get Payment Status
* **Method & Path:** `GET /api/v1/orders/:order_id/payment`
* **Authentication:** JWT Required
* **Success Response (`200 OK`):**
  ```json
  {
    "id": 8,
    "status": "paid",
    "payment_type": "credit_card",
    "gross_amount": "3089.99",
    "midtrans_transaction_id": "mt-trans-992384"
  }
  ```

#### Midtrans Webhook Callback
* **Method & Path:** `POST /api/v1/payments/webhook`
* **Authentication:** Webhook Signature Key check (Calculated: `SHA512(order_id + status_code + gross_amount + server_key)`)
* **Request Body (Midtrans payload example):**
  ```json
  {
    "transaction_time": "2026-06-20 22:30:00",
    "transaction_status": "settlement",
    "transaction_id": "mt-trans-992384",
    "status_message": "midtrans payment notification",
    "status_code": "200",
    "signature_key": "valid_sha512_hash...",
    "payment_type": "credit_card",
    "order_id": "12",
    "gross_amount": "3089.99"
  }
  ```
* **Success Response (`200 OK`):** Empty body or success confirmation.
* **Errors:**
  * `401 Unauthorized` with `{ "error": "Invalid webhook signature" }` (returned if signature checksum fails).
  * `404 Not Found` (Logged internally if transaction isn't found in DB, returns 200 to Midtrans to acknowledge message delivery).

---

### 4.5 Admin Orders Management (`/api/v1/admin/orders`)

#### List All Orders (Admin View)
* **Method & Path:** `GET /api/v1/admin/orders`
* **Authentication:** JWT (Admin Only)
* **Query Parameters:** `page`, `per_page`, `status` (filters by status), `user_id` (filters by specific customer)
* **Success Response (`200 OK`):** Returns a list of all user orders matching the criteria.

#### Update Order Status
* **Method & Path:** `PUT /api/v1/admin/orders/:id/status`
* **Authentication:** JWT (Admin Only)
* **Request Body:**
  ```json
  {
    "status": "processing"
  }
  ```
* **Success Response (`200 OK`):** Returns the updated order object.
* **Errors:** `422 Unprocessable Entity` with `{ "error": "Invalid status transition" }`.
