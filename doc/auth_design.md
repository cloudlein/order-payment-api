# Authentication & Authorization Design

This document outlines the design for JWT-based authentication with Refresh Tokens and Token Blacklisting using Redis.

## 1. Database Schema (PostgreSQL)

### Table: `users`
Stores user identity and credentials.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | BigInt | PK, Auto Increment | Unique identifier |
| `email` | String | Unique, Not Null, Indexed | User's email address |
| `password_digest` | String | Not Null | BCrypt hashed password |
| `name` | String | | Full name |
| `role` | String | Not Null, Default: 'user' | Access level (admin, user, etc.) |
| `otp_code` | String | | Temporary OTP for verification |
| `otp_expires_at`| DateTime | | Expiry for OTP |
| `created_at` | DateTime | Not Null | Timestamp |
| `updated_at` | DateTime | Not Null | Timestamp |

### Table: `refresh_tokens`
Stores long-lived tokens used to generate new Access Tokens.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | BigInt | PK, Auto Increment | Unique identifier |
| `user_id` | BigInt | FK (users.id), Not Null | Owner of the token |
| `token` | String | Unique, Not Null, Indexed | Secure random string |
| `expires_at` | DateTime | Not Null | Expiration timestamp |
| `revoked_at` | DateTime | | Timestamp of manual revocation |
| `created_at` | DateTime | Not Null | Timestamp |
| `updated_at` | DateTime | Not Null | Timestamp |

---

## 2. Redis Design (Token Blacklisting)

Redis is used to store invalidated Access Tokens (JWT) until they naturally expire.

### Access Token Blacklist
When a user logs out, their current JWT is added to a blacklist.

- **Key Pattern:** `blacklist:token:{jti}`
- **Value:** `1`
- **TTL:** Calculated as `JWT_Expiration_Time - Current_Time`.
- **Logic:** Every request with a JWT must check if the `jti` exists in Redis. If it does, the request is rejected.

---

## 3. JWT Structure

### Access Token (Short-lived)
- **Header:** `{ "alg": "HS256", "typ": "JWT" }`
- **Payload:**
  ```json
  {
    "sub": "user_id",
    "jti": "unique_token_id",
    "role": "user_role",
    "iat": 1718330000,
    "exp": 1718333600
  }
  ```

### Refresh Token (Long-lived)
- Stored in the database (`refresh_tokens` table).
- Opaque string (not a JWT) for better security and easier revocation.
- Sent to the client in an `HttpOnly` cookie or secure storage.

---

## 4. Authentication Flow

1. **Login:**
   - User provides email/password.
   - Server validates credentials.
   - Server generates a short-lived **Access Token** (JWT).
   - Server generates a long-lived **Refresh Token** (Opaque string), saves it to DB, and sends it to the client.

2. **Authenticated Request:**
   - Client sends Access Token in `Authorization: Bearer <token>` header.
   - Server validates signature and expiration.
   - Server checks Redis blacklist for the token's `jti`.

3. **Token Refresh:**
   - Client sends Refresh Token when Access Token expires.
   - Server validates Refresh Token against DB (checks `expires_at` and `revoked_at`).
   - Server generates a new Access Token.
   - (Optional) Rotate Refresh Token (issue a new one and revoke the old one).

4. **Logout:**
   - Server adds the current Access Token's `jti` to Redis blacklist.
   - Server marks the Refresh Token as revoked in the database (`revoked_at = now`).
