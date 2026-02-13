# syntax=docker/dockerfile:1.7
############################################
# Base Image
############################################
ARG PHP_BASE_IMAGE=serversideup/php:8.4-fpm-nginx
FROM ${PHP_BASE_IMAGE} AS base

WORKDIR /var/www/html

# Install PHP extensions required for Laravel + MariaDB + Redis + Horizon
USER root
RUN install-php-extensions intl pdo_mysql redis pcntl zip bcmath exif gd


# Drop back to non-root (serversideup/php default user)
USER www-data

############################################
# Development Image
############################################
FROM base AS development

USER root

# Default to 1000 (standard for Linux/WSL2; macOS Docker Desktop maps automatically)
ARG USER_ID=1000
ARG GROUP_ID=1000

# Align www-data UID/GID with the host user so bind-mount files have correct ownership
RUN docker-php-serversideup-set-id www-data ${USER_ID}:${GROUP_ID} && \
    docker-php-serversideup-set-file-permissions --owner ${USER_ID}:${GROUP_ID} && \
    chown -R ${USER_ID}:${GROUP_ID} /composer

USER www-data

############################################
# Production Image
############################################
FROM base AS production

# Copy composer manifests first for better Docker layer caching
COPY --chown=www-data:www-data composer.json composer.lock ./

# Install production dependencies only (no dev packages)
RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-interaction \
    --no-progress \
    --optimize-autoloader

# Copy the full application code (secrets excluded via .dockerignore)
COPY --chown=www-data:www-data . /var/www/html

# Recreate runtime-writable directories excluded by .dockerignore
# and set correct ownership + permissions
USER root
RUN mkdir -p \
    /var/www/html/storage/app/public \
    /var/www/html/storage/framework/cache/data \
    /var/www/html/storage/framework/sessions \
    /var/www/html/storage/framework/views \
    /var/www/html/storage/logs \
    /var/www/html/bootstrap/cache && \
    chown -R www-data:www-data \
        /var/www/html/storage \
        /var/www/html/bootstrap/cache && \
    chmod -R 775 \
        /var/www/html/storage \
        /var/www/html/bootstrap/cache

USER www-data
