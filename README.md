# Docker Laravel

Production-ready Docker setup for Laravel using [serversideup/php](https://serversideup.net/open-source/docker-php/) (FPM-NGINX), MariaDB, and Redis.

## Services

| Service | Description | Container Port | Default Host Port |
|---|---|---|---|
| **php** | Laravel app (PHP-FPM + NGINX) | 8080 / 8443 | 80 / 443 |
| **scheduler** | `schedule:work` (runs every minute) | — | — |
| **horizon** | Redis queue dashboard (profile) | — | — |
| **queue** | Basic `queue:work` (profile) | — | — |
| **reverb** | WebSocket server (profile) | 8000 | 8080 |
| **mariadb** | MariaDB 11 database | 3306 | 33060 |
| **redis** | Redis (Alpine) | 6379 | 63790 |

## Requirements

- Docker Desktop (Windows / macOS) or Docker Engine (Linux)
- Docker Compose v2+

## Project Structure

```
app/
├── .env                        # All configuration (Docker + Laravel)
├── .env.example                # Template (commit this, not .env)
├── .dockerignore               # Excluded from production image
├── Dockerfile                  # Multi-stage: development + production
├── compose.yml                 # Development environment
├── compose.prod.yml            # Production environment (Traefik)
├── docker/
│   └── mariadb/
│       ├── conf.d/
│       │   └── 00-charset.cnf # UTF-8mb4 charset
│       └── init/               # .sql files run on first DB init
├── composer.json
└── ... (Laravel source code)
```

## Quick Start (Development)

### Step 1 — Clone and configure

```powershell
cd C:\Users\aliam\Desktop\docker-laravel\app
```

Open `.env` and review the values. The defaults work out of the box. Key settings:

| Variable | Default | Notes |
|---|---|---|
| `COMPOSE_PROFILES` | `horizon,reverb` | Which optional services to start |
| `HOST_UID` / `HOST_GID` | `1000` | Match your Linux UID; leave 1000 on Windows/macOS |
| `MARIADB_EXPOSED_PORT` | `33060` | Avoids conflict with local MySQL |
| `REDIS_EXPOSED_PORT` | `63790` | Avoids conflict with local Redis |

### Step 2 — Build and start

```powershell
docker compose up -d --build
```

This builds the development image and starts all services. Wait for all healthchecks to pass:

```powershell
docker compose ps
```

All services should show `(healthy)`.

### Step 3 — Generate application key

```powershell
docker compose exec php php artisan key:generate
```

### Step 4 — Run migrations

```powershell
docker compose exec php php artisan migrate
```

### Step 5 — Open the app

- **Web app**: http://localhost
- **Health check**: http://localhost/up
- **Horizon dashboard**: http://localhost/horizon
- **MariaDB** (from DB GUI): `localhost:33060` user `laravel` / password `secret`
- **Redis** (from Redis GUI): `localhost:63790` password `redissecret`

## Profiles

Horizon, Queue, and Reverb are controlled via the `COMPOSE_PROFILES` variable in `.env`. This prevents accidentally running both Horizon and Queue at the same time (which would cause double job processing).

| `.env` value | What starts |
|---|---|
| `COMPOSE_PROFILES=horizon,reverb` | php + scheduler + horizon + reverb + mariadb + redis |
| `COMPOSE_PROFILES=horizon` | php + scheduler + horizon + mariadb + redis |
| `COMPOSE_PROFILES=queue,reverb` | php + scheduler + queue + reverb + mariadb + redis |
| `COMPOSE_PROFILES=queue` | php + scheduler + queue + mariadb + redis |
| *(empty or not set)* | php + scheduler + mariadb + redis *(no job processing)* |

**Rule**: Use `horizon` OR `queue`, never both.

- `horizon` requires `laravel/horizon` package installed
- `reverb` requires `laravel/reverb` package installed
- `queue` works with plain Laravel, no extra packages

### Install optional packages

```powershell
# If using Horizon profile
docker compose exec php composer require laravel/horizon
docker compose exec php php artisan horizon:install

# If using Reverb profile
docker compose exec php composer require laravel/reverb
docker compose exec php php artisan vendor:publish --provider="Laravel\Reverb\ReverbServiceProvider" --tag="reverb-config"
```

After installing, restart the affected containers:

```powershell
docker compose restart horizon reverb
```

## Common Commands

```powershell
# Start all services
docker compose up -d

# Start with rebuild (after Dockerfile changes)
docker compose up -d --build

# Stop all services (data preserved)
docker compose down

# Stop and delete all data (volumes)
docker compose down -v

# View running containers
docker compose ps

# View logs (follow mode)
docker compose logs -f php
docker compose logs -f horizon
docker compose logs -f reverb

# Run artisan commands
docker compose exec php php artisan migrate
docker compose exec php php artisan tinker
docker compose exec php php artisan queue:restart
docker compose exec php php artisan horizon:terminate

# Run composer
docker compose exec php composer install
docker compose exec php composer require some/package

# Access container shell
docker compose exec php bash

# Restart a specific service
docker compose restart php
docker compose restart horizon
```

## How It Works

### Dockerfile (Multi-Stage Build)

The Dockerfile has three stages:

1. **base** — Installs `pdo_mysql`, `redis`, `pcntl` extensions on top of `serversideup/php:8.4-fpm-nginx`
2. **development** — Remaps `www-data` UID/GID to match the host user for seamless bind-mount permissions
3. **production** — Copies code into the image, runs `composer install --no-dev`, creates storage directories with `chmod 775`

### Development Compose (`compose.yml`)

- **php** service builds the `development` stage and bind-mounts the project directory
- All worker services (scheduler, horizon, queue, reverb) share the same image and bind-mount
- MariaDB and Redis ports are exposed to the host so you can use GUI tools
- `AUTORUN_ENABLED` is hardcoded to `false` in development

### Production Compose (`compose.prod.yml`)

- **Traefik** handles TLS termination with automatic Let's Encrypt certificates
- **php** service builds the `production` stage (code baked into image, no bind-mounts)
- `AUTORUN_ENABLED` runs `migrate`, `optimize`, `storage:link`, and all caching commands on container startup
- MariaDB charset is set via command flags (no external config files needed on the server)
- No ports directly exposed except through Traefik (80/443)

### Healthchecks

| Service | Method | Timeout |
|---|---|---|
| php | Built-in HTTP check on `/up` | NGINX default |
| scheduler | `healthcheck-schedule` (serversideup) | 10s |
| horizon | `healthcheck-horizon` (serversideup) | 10s |
| queue | `healthcheck-queue` (serversideup) | 10s |
| reverb | `healthcheck-reverb` (serversideup) | 10s |
| mariadb | `mariadb-admin ping` | 3s |
| redis | `redis-cli ping` | 3s |

### Permissions

- The `serversideup/php` image runs as `www-data` (non-root) by default
- In development, `www-data` UID/GID is remapped to match `HOST_UID`/`HOST_GID` from `.env`
- In production, `storage/` and `bootstrap/cache/` are set to `775` owned by `www-data`
- On Windows/macOS Docker Desktop, leave `HOST_UID=1000` (the VM handles mapping)
- On Linux, run `id -u` and `id -g` and set those values in `.env`

## Production Deployment

### Step 1 — Prepare `.env` for production

Copy `.env` to your server and change these values:

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com

SSL_MODE=off
AUTORUN_ENABLED=true

APP_DOMAIN=app.example.com
REVERB_DOMAIN=reverb.example.com
TRAEFIK_ACME_EMAIL=you@example.com

REVERB_HOST=reverb.example.com
REVERB_PORT=443
REVERB_SCHEME=https
```

Use strong, unique passwords for `DB_PASSWORD`, `MARIADB_PASSWORD`, `MARIADB_ROOT_PASSWORD`, and `REDIS_PASSWORD`.

### Step 2 — Build the production image

```bash
docker compose -f compose.prod.yml build php
```

### Step 3 — Start production

```bash
docker compose -f compose.prod.yml up -d
```

Traefik automatically provisions Let's Encrypt TLS certificates. The `AUTORUN_ENABLED=true` setting triggers automatic `migrate`, `optimize`, `storage:link`, route/config/view/event caching on every container startup.

### Step 4 — Verify

```bash
docker compose -f compose.prod.yml ps
docker compose -f compose.prod.yml logs -f php
```

## Environment Variable Reference

All configuration is in `.env`. The file is organized into sections:

| Section | Variables |
|---|---|
| Docker Compose | `COMPOSE_PROJECT_NAME`, `COMPOSE_PROFILES` |
| Build | `PHP_BASE_IMAGE`, `APP_IMAGE`, `APP_IMAGE_TAG` |
| Host Ports | `APP_HTTP_PORT`, `APP_HTTPS_PORT`, `REVERB_EXPOSED_PORT`, `MARIADB_EXPOSED_PORT`, `REDIS_EXPOSED_PORT` |
| PHP/NGINX | `SSL_MODE`, `PHP_OPCACHE_ENABLE`, `PHP_MEMORY_LIMIT`, `PHP_MAX_EXECUTION_TIME`, `PHP_UPLOAD_MAX_FILE_SIZE`, `PHP_POST_MAX_SIZE`, `NGINX_CLIENT_MAX_BODY_SIZE` |
| Laravel | `APP_NAME`, `APP_ENV`, `APP_KEY`, `APP_DEBUG`, `APP_URL`, `LOG_CHANNEL`, `LOG_LEVEL` |
| Database | `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` |
| MariaDB | `MARIADB_VERSION`, `MARIADB_ROOT_PASSWORD`, `MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD` |
| Redis | `REDIS_VERSION`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |
| Cache/Queue | `CACHE_STORE`, `QUEUE_CONNECTION`, `SESSION_DRIVER`, `QUEUE_TRIES` |
| Reverb | `REVERB_APP_ID`, `REVERB_APP_KEY`, `REVERB_APP_SECRET`, `REVERB_HOST`, `REVERB_PORT`, `REVERB_SCHEME`, `REVERB_SERVER_HOST`, `REVERB_SERVER_PORT` |
| Traefik | `TRAEFIK_VERSION`, `TRAEFIK_DASHBOARD`, `TRAEFIK_ACME_EMAIL`, `APP_DOMAIN`, `REVERB_DOMAIN` |
| Automations | `AUTORUN_ENABLED`, `AUTORUN_LARAVEL_OPTIMIZE`, `AUTORUN_LARAVEL_MIGRATION`, etc. |

## Data Persistence

### What is safe and what is not

| Data | Development | Production | Survives `down` | Survives `down -v` |
|---|---|---|---|---|
| MariaDB | `mariadb_data` volume | `mariadb_data` volume | Yes | **NO** |
| Redis | `redis_data` volume | `redis_data` volume | Yes | **NO** |
| Laravel storage (uploads, logs) | Host filesystem (bind mount) | `storage_data` volume | Yes | **NO** |
| Laravel source code | Host filesystem (bind mount) | Baked into image | Yes | Yes |
| Traefik certificates | — | `traefik_certs` volume | Yes | **NO** |

**Key rule**: `docker compose down` is safe. `docker compose down -v` deletes all named volumes (database, uploads, everything). Only use `-v` when you want a full reset.

### Where volumes physically live

Docker named volumes are managed by Docker and stored at:
- **Windows**: `\\wsl$\docker-desktop-data\data\docker\volumes\` (inside WSL2)
- **Linux**: `/var/lib/docker/volumes/`
- **macOS**: Inside the Docker Desktop VM

You don't need to access them directly. Use `docker compose exec` or GUI tools to interact with the data.

## Horizon Security

By default, the Horizon dashboard (`/horizon`) is **open to everyone in `local` environment** and **blocked in production**.

To allow specific users in production, edit `app/Providers/HorizonServiceProvider.php`:

```php
protected function gate(): void
{
    Gate::define('viewHorizon', function ($user = null) {
        return in_array(optional($user)->email, [
            'admin@example.com',
            'another-admin@example.com',
        ]);
    });
}
```

Only authenticated users whose email is in that list can access `/horizon` in production. Everyone else gets a 403.

## Troubleshooting

### Port conflict on startup

If you see `bind: An attempt was made to access a socket in a way forbidden`, another process is using that port. Change the conflicting port in `.env`:

```env
MARIADB_EXPOSED_PORT=33061
REDIS_EXPOSED_PORT=63791
APP_HTTP_PORT=8000
```

### Horizon or Reverb keeps restarting

The `laravel/horizon` or `laravel/reverb` package is not installed. Install it:

```powershell
docker compose exec php composer require laravel/horizon
docker compose exec php php artisan horizon:install
docker compose restart horizon
```

Or remove the profile from `COMPOSE_PROFILES` in `.env` if you don't need it.

### Permission denied errors on Linux

Your `HOST_UID`/`HOST_GID` in `.env` doesn't match your system user. Fix it:

```bash
# Find your UID/GID
id -u    # e.g. 1000
id -g    # e.g. 1000

# Set in .env
HOST_UID=1000
HOST_GID=1000

# Rebuild
docker compose up -d --build
```

### Database connection refused

MariaDB might not be ready yet. The `depends_on: condition: service_healthy` ensures the web container waits, but if you run artisan commands manually right after startup, wait a few seconds:

```powershell
docker compose ps   # wait until mariadb shows (healthy)
docker compose exec php php artisan migrate
```

### Reset everything from scratch

```powershell
docker compose down -v
docker compose up -d --build
docker compose exec php php artisan key:generate
docker compose exec php php artisan migrate
```
