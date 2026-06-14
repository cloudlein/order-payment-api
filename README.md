# Order Payment API

A RESTful API for order and payment management built with Rails 8.1, PostgreSQL, and JWT-based authentication. Integrates with Midtrans as the payment gateway.

- [Authentication & Authorization Design](doc/auth_design.md)

---

## Requirements

| Dependency | Version |
|---|---|
| Ruby | 4.0.3 |
| Rails | ~> 8.1.3 |
| PostgreSQL | 16+ |
| Redis | 7+ |
| Docker & Docker Compose | Latest (optional) |

---

## Installation

### Option A: Docker (Recommended)

This method requires only Docker and Docker Compose. No local Ruby or PostgreSQL installation is needed.

**1. Clone the repository**

```bash
git clone <repository-url>
cd order-payment-api
```

**2. Configure credentials**

Copy the `config/master.key` value and export it as an environment variable, or create a `.env` file at the project root:

```
RAILS_MASTER_KEY=<value from config/master.key>
```

> Do not commit `config/master.key` or `.env` to version control.

**3. Build and start all services**

```bash
docker compose up --build
```

This starts the following services:

| Service | Image | Port |
|---|---|---|
| `db` | postgres:16-alpine | 5432 |
| `redis` | redis:7-alpine | 6379 |
| `web` | Local build (Rails) | 3000 |

**4. Initialize the database**

In a separate terminal, run:

```bash
docker compose exec web rails db:create db:migrate
```

To load seed data:

```bash
docker compose exec web rails db:seed
```

**5. Verify the server is running**

```
http://localhost:3000/up
```

A `200 OK` response confirms the application is running.

---

### Option B: Local Installation (Without Docker)

**1. Install Ruby 4.0.3**

Using rbenv:

```bash
rbenv install 4.0.3
rbenv local 4.0.3
```

Using asdf:

```bash
asdf install ruby 4.0.3
asdf local ruby 4.0.3
```

**2. Clone the repository**

```bash
git clone <repository-url>
cd order-payment-api
```

**3. Install gem dependencies**

```bash
bundle install
```

**4. Configure the database**

Ensure PostgreSQL is running on port `5432`. Set the following environment variables to match your local PostgreSQL credentials:

```bash
export DB_HOST=localhost
export DB_USERNAME=postgres
export DB_PASSWORD=password
```

**5. Create and migrate the database**

```bash
rails db:create
rails db:migrate
```

To load seed data:

```bash
rails db:seed
```

**6. Start the development server**

```bash
rails server
```

The API will be available at:

```
http://localhost:3000
```

---

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `DB_HOST` | PostgreSQL host | `localhost` |
| `DB_USERNAME` | PostgreSQL username | `postgres` |
| `DB_PASSWORD` | PostgreSQL password | `password` |
| `REDIS_URL` | Redis connection URL | `redis://localhost:6379/1` |
| `RAILS_ENV` | Rails environment | `development` |
| `RAILS_MASTER_KEY` | Decryption key for credentials | _(from `config/master.key`)_ |
| `RAILS_MAX_THREADS` | Puma thread pool size | `5` |

---

## Docker Reference

```bash
# Start services in the background
docker compose up -d

# Stream application logs
docker compose logs -f web

# Open a shell inside the Rails container
docker compose exec web bash

# Open the Rails console
docker compose exec web rails console

# Run database migrations
docker compose exec web rails db:migrate

# Stop all services
docker compose down

# Stop all services and remove volumes (resets the database)
docker compose down -v
```

---

## Running Tests

```bash
# Run the full test suite
rails test

# Run model tests only
rails test test/models

# Run controller tests only
rails test test/controllers

# Static security analysis
bundle exec brakeman --no-pager

# Dependency vulnerability audit
bundle exec bundler-audit check

# Code style linting
bundle exec rubocop
```

---

## Project Structure

```
order-payment-api/
├── app/
│   ├── controllers/
│   │   ├── api/v1/          # Versioned API controllers
│   │   └── concerns/        # Shared controller modules
│   ├── models/              # ActiveRecord models
│   └── services/            # Service objects for business logic
├── config/
│   ├── routes.rb            # Route definitions
│   └── initializers/        # Application initializers (JWT, CORS, etc.)
├── db/
│   ├── migrate/             # Database migrations
│   └── seeds.rb             # Seed data
├── doc/                     # Supporting documentation
├── docker-compose.yml       # Compose service definitions
└── Dockerfile               # Container build instructions
```

---

## Documentation

- [Authentication & Authorization Design](doc/auth_design.md)
- API Reference: `doc/api.md` _(in progress)_
