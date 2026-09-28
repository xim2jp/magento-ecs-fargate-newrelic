# syntax=docker/dockerfile:1.7
#
# Magento Open Source image for ECS Fargate.
# One image, three roles selected by the container command:
#   php-fpm (default) | nginx -g 'daemon off;' | cron | install
#
# Build-time: Magento is fetched from the Mage-OS mirror (no repo.magento.com keys),
# DI is compiled and static content is deployed (production mode). The New Relic PHP
# agent is installed but only enabled at runtime when NEW_RELIC_LICENSE_KEY is set.
# Run-time: entrypoint.sh renders app/etc/env.php from environment variables.

ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-bookworm

ARG MAGENTO_VERSION=2.4.9
ARG INSTALL_SAMPLE_DATA=true
ARG NR_PHP_AGENT_VERSION=12.11.0.40

ENV MAGE_ROOT=/var/www/magento \
    MAGE_MODE=production \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_HOME=/tmp/composer

# --- OS packages: nginx (served from the same image), mysql client (install task), tools
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx git unzip curl ca-certificates default-mysql-client procps \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

# --- PHP extensions required by Magento 2.4.9
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN install-php-extensions bcmath ftp gd intl pdo_mysql soap sockets xsl zip opcache

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

COPY php/zz-magento.ini /usr/local/etc/php/conf.d/zz-magento.ini
COPY php/zz-www.conf   /usr/local/etc/php-fpm.d/zz-www.conf

# --- New Relic PHP agent (disabled by default; entrypoint enables it when a key exists)
RUN set -eux; \
    cd /tmp; \
    curl -fsSL "https://download.newrelic.com/php_agent/archive/${NR_PHP_AGENT_VERSION}/newrelic-php5-${NR_PHP_AGENT_VERSION}-linux.tar.gz" | tar -xz; \
    NR_INSTALL_SILENT=1 NR_INSTALL_USE_CP_NOT_LN=1 "/tmp/newrelic-php5-${NR_PHP_AGENT_VERSION}-linux/newrelic-install" install; \
    rm -rf /tmp/newrelic-php5-* /tmp/nrinstall*; \
    mkdir -p /var/log/newrelic; \
    printf 'newrelic.enabled = false\n' > /usr/local/etc/php/conf.d/zz-newrelic.ini

# --- Magento Open Source from the Mage-OS mirror
WORKDIR ${MAGE_ROOT}
RUN composer create-project --repository-url=https://mirror.mage-os.org/ \
      "magento/project-community-edition=${MAGENTO_VERSION}" . \
 && composer clear-cache

# Sample data packages are discovered from the "suggest" sections shipped with the
# core modules (same list bin/magento sampledata:deploy would use).
RUN if [ "${INSTALL_SAMPLE_DATA}" = "true" ]; then \
      pkgs="$(grep -rhoE '"magento/(module-)?[a-z0-9-]*sample-data[a-z0-9-]*": *"Sample Data version: *[^"]+"' vendor/magento/*/composer.json \
        | sed -E 's/"([^"]+)": *"Sample Data version: *([^"]+)"/\1:\2/' | sort -u | tr '\n' ' ')"; \
      echo "Sample data packages: ${pkgs}"; \
      composer require --no-interaction ${pkgs} \
      && composer clear-cache; \
    fi

# --- Build-time compilation (no database needed): module list, DI, static assets.
# Static deploy needs the default website/store to build URLs; build-scopes.php writes
# the default scopes into config.php for the duration of the deploy (see file header).
COPY build-scopes.php /usr/local/lib/magento/build-scopes.php
RUN php bin/magento module:enable --all \
 && (php bin/magento module:disable Magento_AdminAdobeImsTwoFactorAuth || true) \
 && php bin/magento module:disable Magento_TwoFactorAuth \
 && php bin/magento setup:di:compile \
 && php /usr/local/lib/magento/build-scopes.php app/etc/config.php add \
 && php bin/magento setup:static-content:deploy -f --jobs 4 en_US \
 && php /usr/local/lib/magento/build-scopes.php app/etc/config.php remove \
 && rm -rf var/cache var/page_cache var/tmp var/log/* \
 && chown -R www-data:www-data ${MAGE_ROOT}

# --- runtime config / scripts
COPY nginx/nginx.conf   /etc/nginx/nginx.conf
COPY nginx/magento.conf /etc/nginx/conf.d/magento.conf
COPY render-env.php     /usr/local/lib/magento/render-env.php
COPY --chmod=0755 entrypoint.sh magento-install.sh magento-cron.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /usr/local/bin/magento-install.sh /usr/local/bin/magento-cron.sh \
      /usr/local/lib/magento/render-env.php /etc/nginx/nginx.conf /etc/nginx/conf.d/magento.conf \
 && nginx -t

EXPOSE 8080 9000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]
