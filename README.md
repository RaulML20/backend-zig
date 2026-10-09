# backend-zig

A small REST API written in [Zig](https://ziglang.org/) **without any web framework**.
The HTTP server loop, the router, the layered architecture, authentication and security
are all built by hand on top of Zig's standard library, just to understand how a backend
works under the hood.

## Why

This is a personal project. Instead of reaching for a framework (like http.zig or Zap), the
whole thing is assembled by hand: route matching, middleware, the request lifecycle and a
clean separation of concerns. It is intentionally simple but follows the same layered
structure you would find in a production backend.

## Features

- **No framework**: built directly on `std.http.Server` and `std.Io` networking, one
  concurrent task per connection (at most 256 at once), keep-alive support. Meant to run
  behind a reverse proxy (nginx, Cloudflare) that terminates TLS and handles slow clients.
- **Custom Trie-based router** with support for static segments, dynamic params
  (`/users/read/:id`) and per-route authentication flags.
- **Layered architecture**: Route → Controller → Service → Repository → Entity.
- **PostgreSQL** access through [pg.zig](https://github.com/karlseguin/pg.zig) (connection
  pool), with DTOs to shape input/output.
- **JWT authentication** (HS256, implemented with `std.crypto`) read from a cookie, applied
  per route via middleware.
- **Security headers** recommended by OWASP for APIs and a small **CORS** handler with
  credentials, configured through `CORS_ORIGINS`.
- **Centralized error handling**: every layer returns an error from a closed error set and a
  single exhaustive table maps it to an HTTP status and message.
- **Transaction helper** (`withTransaction`) for operations that run several statements.
- **Per-request arena**: everything a request allocates is freed in one go after responding.

## Architecture

A request flows through clearly separated layers, each with a single responsibility:

```
HTTP request
   │
   ▼
main.zig: server loop, global error handling, security & CORS
   │
   ▼
Router (Trie): matches path, extracts params, checks auth
   │
   ▼
Route: wires the endpoint to a controller action
   │
   ▼
Controller: parses/validates the request, builds the response
   │
   ▼
Service: business logic
   │
   ▼
Repository: database queries (PostgreSQL)
   │
   ▼
Entity / DTO: data models and serialization
```

### Project structure

```
src/
├── main.zig
├── config/
│   ├── cors.zig
│   ├── database.zig
│   ├── env.zig
│   ├── security.zig
│   └── transactions.zig
├── controllers/
├── dtos/
├── entities/
├── http/
│   └── context.zig
├── middleware/
│   └── auth.zig
├── repositories/
├── router/
│   ├── router.zig
│   └── trie_node.zig
├── routes/
├── services/
└── utils/
    ├── exception.zig
    └── jwt.zig
```

- `main.zig`: entry point. Loads the config, opens the pool, wires the routes and serves connections.
- `config/env.zig`: `.env` loader.
- `config/database.zig`: connection pool + PostgreSQL error mapping.
- `config/transactions.zig`: transaction helper.
- `http/context.zig`: per-request state (request, params, user id, response).
- `utils/exception.zig`: error → status/message table.
- `utils/jwt.zig`: HS256 encode/decode.

### Notes

- **Errors**: code returns `error.UserNotFound` and `utils/exception.zig` maps it to `404` +
  `"User not found"`. Every function on the request path returns `exception.Error`, so the
  compiler checks that each error has a mapping. Database failures are logged on the server
  and reach the client only as `Database error`.
- **Handlers**: routes bind a controller instance and one of its methods
  (`Handler.bind(user_controller, UserController.read)`), since Zig has no closures.
- **Memory**: each request gets an arena, so DTOs, query results and JSON live until the
  response is sent.
- **Request body**: limited to 1 MiB (`413 Body too large`).
- **Config**: variables already set in the real environment win over `.env`. `ENV_FILE`
  points to another `.env` file and `HOST` sets the bind address (default `127.0.0.1`).

## API

All routes are prefixed with `/api/v1`.

> **Note:** These routes are **examples** to demonstrate the architecture, in particular how
> per-route authentication is wired through the router. The auth configuration shown here is
> intentionally minimal and would not reflect a real-world setup (e.g. `POST /add` would
> normally be a protected route).

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/v1/users/readAll` | No | List all users |
| GET | `/api/v1/users/read/:id` | Yes | Get a user by id |
| POST | `/api/v1/users/add` | No | Create a user |

Responses follow a simple JSON envelope:

```json
{ "ok": 1, "data": { "id": 1, "name": "Raúl", "email": "raul@example.com" } }
```

Errors, including 401, 404 and 405, return the same shape with the matching HTTP status code:

```json
{ "ok": 0, "error": "User not found" }
```

Protected routes expect a JWT in a `token` cookie, signed with `SECRET_KEY` (HS256), with
an `exp` claim and a non-empty `sub`.

## Requirements

- [Zig](https://ziglang.org/download/) `0.17.0`
- PostgreSQL

## Getting started

1. **Create the database table**

   ```sql
   CREATE TABLE users (
     id SERIAL PRIMARY KEY,
     name TEXT NOT NULL,
     email TEXT NOT NULL
   );
   ```

2. **Configure environment variables**

   Copy `src/config/.env.example` to `src/config/.env` (this file is git-ignored) and fill it in.

3. **Run the server** (from the project root, dependencies are fetched on the first build)

   ```bash
   zig build run
   ```

   The server will start on `http://127.0.0.1:8080` (or the `PORT` you set).

## Build

```bash
zig build -Doptimize=ReleaseSafe
./zig-out/bin/backend-zig
```

The build copies `src/config/.env` next to the binary, and the binary reads the `.env` in
its own folder wherever it is started from; use `ENV_FILE` to point elsewhere.

## Tests

```bash
zig build test
```

Unit tests cover the router, JWT, auth middleware, CORS, DTO validation, `.env` parsing and
error mapping. They do not need a database.

## License

[MIT](LICENSE)

## Author

- [Raúl](https://github.com/RaulML20): creator and maintainer