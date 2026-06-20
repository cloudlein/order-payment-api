# Feature Flows & Sequences

This document provides sequential flow diagrams (using Mermaid) for the main features of the Order Payment API.

---

## 1. Authentication Flow (JWT & Refresh Token)

This diagram describes the user registration, login, token rotation (refresh), and logout sequence.

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client App
    participant API as Rails API
    database DB as PostgreSQL DB

    Note over Client, DB: Registration
    Client->>API: POST /api/v1/auth/register (email, name, password)
    API->>DB: Create User record (password encrypted via bcrypt)
    DB-->>API: User created
    API-->>Client: 201 Created (User details)

    Note over Client, DB: Login
    Client->>API: POST /api/v1/auth/login (email, password)
    API->>DB: Find user by email & authenticate password
    API->>DB: Create RefreshToken record (SecureRandom.hex)
    API->>API: Generate JWT Access Token (signed with HS256, 24h TTL)
    API-->>Client: 200 OK (access_token, refresh_token, expires_in)

    Note over Client, DB: Token Refresh (Rotation)
    Client->>API: POST /api/v1/auth/refresh (refresh_token)
    API->>DB: Find active RefreshToken
    API->>DB: Revoke old RefreshToken (set revoked_at)
    API->>DB: Generate new RefreshToken record
    API->>API: Generate new JWT Access Token
    API-->>Client: 200 OK (new access_token, new refresh_token)

    Note over Client, DB: Logout
    Client->>API: POST /api/v1/auth/logout (refresh_token) (JWT Authed)
    API->>DB: Find RefreshToken and set revoked_at
    API-->>Client: 200 OK (Logged out successfully)
```

---

## 2. Order Lifecycle & Stock Management Flow

This diagram outlines how an order is created (with stock validation, price snapshotting, and stock decrementing) and cancelled.

```mermaid
sequenceDiagram
    autonumber
    actor Client as Client App
    participant API as Rails API
    database DB as PostgreSQL DB

    Note over Client, DB: Order Creation (POST /api/v1/orders)
    Client->>API: POST /api/v1/orders (order_items_attributes)
    API->>DB: Begin Transaction & lock products (with_lock)
    API->>DB: Verify stock levels
    alt Insufficient Stock
        API->>DB: Rollback
        API-->>Client: 409 Conflict (Insufficient stock error)
    else Stock Sufficient
        API->>DB: Snapshot product price to order_item.price
        API->>API: Calculate total_amount (quantity * item price)
        API->>DB: Decrement product stock (stock - quantity)
        API->>DB: Save Order (status: pending) & Order Items
        API->>DB: Commit Transaction
        API-->>Client: 201 Created (Order details)
    end

    Note over Client, DB: Order Cancellation (PUT /api/v1/orders/:id/cancel)
    Client->>API: PUT /api/v1/orders/:id/cancel
    API->>DB: Find Order (must be pending)
    API->>DB: Begin Transaction & lock products
    API->>DB: Increment product stock (restore stock + quantity)
    API->>DB: Update Order status to 'cancelled'
    API->>DB: Commit Transaction
    API-->>Client: 200 OK (Updated order status)
```

---

## 3. Payment Flow & Midtrans Integration

This diagram describes payment initiation via Midtrans Snap and the server-to-server webhook notification callback.

```mermaid
sequenceDiagram
    autonumber
    actor User as User / Browser
    participant Client as Client App
    participant API as Rails API
    participant Midtrans as Midtrans API
    database DB as PostgreSQL DB

    Note over User, Midtrans: 1. Payment Initiation
    Client->>API: POST /api/v1/orders/:order_id/payment
    API->>DB: Check order (must be pending and unpaid)
    API->>Midtrans: Call Snap API (order_id, gross_amount, credentials)
    Midtrans-->>API: Return Snap Token & Redirect URL
    API->>DB: Create Payment record (status: pending)
    API-->>Client: 201 Created (snap_token, redirect_url)

    Note over User, Midtrans: 2. Customer Payment
    Client->>User: Launch Midtrans Snap UI
    User->>Midtrans: Perform payment (Credit Card, GoPay, Bank Transfer)
    Midtrans-->>User: Payment status success/pending screen

    Note over User, Midtrans: 3. Webhook Notification Callback
    Midtrans->>API: POST /api/v1/payments/webhook (Notification payload)
    API->>API: Validate signature key (SHA512 checksum)
    alt Invalid Signature
        API-->>Midtrans: 401 Unauthorized
    else Valid Signature
        API->>DB: Find Payment by midtrans_transaction_id
        API->>DB: Update Payment status (e.g., settlement -> paid)
        opt Status is Paid
            API->>DB: Update Order status to 'completed'
        end
        API-->>Midtrans: 200 OK
    end
```
