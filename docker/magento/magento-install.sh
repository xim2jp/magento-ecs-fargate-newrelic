#!/bin/bash
# One-off install / upgrade task.
#  - fresh database  -> bin/magento setup:install (+ sample data via module InstallData)
#  - existing install -> bin/magento setup:upgrade (schema/data patches after image updates)
# Runs as root; Magento commands run as www-data.
set -euo pipefail

: "${MAGE_ROOT:=/var/www/magento}"
cd "$MAGE_ROOT"

: "${MAGENTO_DB_ADMIN_USER:=$MAGENTO_DB_USER}"
mage() { runuser -u www-data -- php -d memory_limit=-1 bin/magento "$@"; }
mysql_admin() { mysql -h "$MAGENTO_DB_HOST" -u "$MAGENTO_DB_ADMIN_USER" -p"$MAGENTO_DB_PASSWORD" -N -s -e "$1"; }
mysql_q() { mysql -h "$MAGENTO_DB_HOST" -u "$MAGENTO_DB_USER" -p"$MAGENTO_DB_PASSWORD" -N -s -e "$1"; }

echo "== $(date -Is) waiting for MySQL at ${MAGENTO_DB_HOST} (admin user ${MAGENTO_DB_ADMIN_USER})"
for _ in $(seq 1 60); do
  if mysqladmin ping -h "$MAGENTO_DB_HOST" -u "$MAGENTO_DB_ADMIN_USER" -p"$MAGENTO_DB_PASSWORD" --silent 2>/dev/null; then break; fi
  sleep 5
done
mysqladmin ping -h "$MAGENTO_DB_HOST" -u "$MAGENTO_DB_ADMIN_USER" -p"$MAGENTO_DB_PASSWORD" --silent

# Dedicated application user with direct grants on the Magento schema. The RDS master
# user holds its privileges via rds_superuser_role, which Magento's DbValidator ignores.
if [ "$MAGENTO_DB_USER" != "$MAGENTO_DB_ADMIN_USER" ]; then
  echo "== ensuring application DB user ${MAGENTO_DB_USER}"
  mysql_admin "CREATE USER IF NOT EXISTS '${MAGENTO_DB_USER}'@'%' IDENTIFIED BY '${MAGENTO_DB_PASSWORD}'; \
               ALTER USER '${MAGENTO_DB_USER}'@'%' IDENTIFIED BY '${MAGENTO_DB_PASSWORD}'; \
               GRANT ALL PRIVILEGES ON \`${MAGENTO_DB_NAME}\`.* TO '${MAGENTO_DB_USER}'@'%'; \
               FLUSH PRIVILEGES;"
fi

echo "== waiting for OpenSearch at ${MAGENTO_OPENSEARCH_HOST}:${MAGENTO_OPENSEARCH_PORT}"
for _ in $(seq 1 60); do
  if curl -fsS "${MAGENTO_OPENSEARCH_HOST}:${MAGENTO_OPENSEARCH_PORT}/" >/dev/null 2>&1; then break; fi
  sleep 5
done
curl -fsS "${MAGENTO_OPENSEARCH_HOST}:${MAGENTO_OPENSEARCH_PORT}/" | head -c 400; echo

echo "== checking Valkey at ${MAGENTO_REDIS_HOST}:${MAGENTO_REDIS_PORT:-6379}"
timeout 5 bash -c "</dev/tcp/${MAGENTO_REDIS_HOST}/${MAGENTO_REDIS_PORT:-6379}" && echo "valkey reachable"

echo "== grants for ${MAGENTO_DB_USER} (RDS grants most privileges through rds_superuser_role)"
mysql_q "SHOW GRANTS" || true
mysql_q "SELECT CURRENT_ROLE()" || true

# pub/media is an EFS mount that hides the media files composer placed in the image.
# The sample-data media package keeps its sources under vendor/, so seed EFS from there
# (no overwrite: -n) so product images and CMS banners exist at runtime.
if [ -d vendor/magento/sample-data-media ]; then
  echo "== seeding pub/media (EFS) with sample data media"
  for d in catalog wysiwyg downloadable; do
    [ -d "vendor/magento/sample-data-media/$d" ] && cp -an "vendor/magento/sample-data-media/$d" pub/media/
  done
  chown -R www-data:www-data pub/media
  echo "   media files on pub/media: $(find pub/media -type f | wc -l)"
fi

# Print Magento's own logs when the container exits (they live only inside this container)
dump_logs() {
  echo "== var/log/system.log (ERROR/CRITICAL, last 40)"
  grep -E "ERROR|CRITICAL" var/log/system.log 2>/dev/null | grep -v "No cache server" | tail -n 40 | cut -c1-900
  echo "== var/log/exception.log (last 40)"
  tail -n 40 var/log/exception.log 2>/dev/null | cut -c1-900
}
trap dump_logs EXIT

installed=$(mysql_q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MAGENTO_DB_NAME}' AND table_name='core_config_data'")
if [ "$installed" = "0" ]; then
  echo "== $(date -Is) fresh database: running setup:install (sample data: ${MAGENTO_INSTALL_SAMPLE_DATA:-false})"
  mage setup:install \
    --base-url="${MAGENTO_BASE_URL}" \
    --db-host="${MAGENTO_DB_HOST}" \
    --db-name="${MAGENTO_DB_NAME}" \
    --db-user="${MAGENTO_DB_USER}" \
    --db-password="${MAGENTO_DB_PASSWORD}" \
    --key="${MAGENTO_CRYPT_KEY}" \
    --backend-frontname="${MAGENTO_ADMIN_FRONTNAME:-admin}" \
    --admin-firstname=Admin \
    --admin-lastname=User \
    --admin-email="${MAGENTO_ADMIN_EMAIL}" \
    --admin-user="${MAGENTO_ADMIN_USER}" \
    --admin-password="${MAGENTO_ADMIN_PASSWORD}" \
    --language="${MAGENTO_LOCALE:-en_US}" \
    --currency="${MAGENTO_CURRENCY:-JPY}" \
    --timezone="${MAGENTO_TIMEZONE:-Asia/Tokyo}" \
    --use-rewrites=1 \
    --search-engine=opensearch \
    --opensearch-host="${MAGENTO_OPENSEARCH_HOST}" \
    --opensearch-port="${MAGENTO_OPENSEARCH_PORT}" \
    --opensearch-index-prefix=magento2 \
    --opensearch-enable-auth=0 \
    --opensearch-timeout=15 \
    --session-save=redis \
    --session-save-redis-host="${MAGENTO_REDIS_HOST}" \
    --session-save-redis-port="${MAGENTO_REDIS_PORT:-6379}" \
    --session-save-redis-db=2 \
    --cache-backend=redis \
    --cache-backend-redis-server="${MAGENTO_REDIS_HOST}" \
    --cache-backend-redis-port="${MAGENTO_REDIS_PORT:-6379}" \
    --cache-backend-redis-db=0 \
    --page-cache=redis \
    --page-cache-redis-server="${MAGENTO_REDIS_HOST}" \
    --page-cache-redis-port="${MAGENTO_REDIS_PORT:-6379}" \
    --page-cache-redis-db=1 \
    --skip-db-validation \
    --no-interaction
else
  echo "== $(date -Is) database already installed: skipping setup:install"
fi

# Replace the installer-written env.php with the environment-driven one used by
# the web/cron containers (same crypt key, adds Varnish + OpenSearch overrides).
php /usr/local/lib/magento/render-env.php > app/etc/env.php
chown www-data:www-data app/etc/env.php

echo "== $(date -Is) setup:upgrade"
mage setup:upgrade --keep-generated

echo "== indexers: schedule mode + full reindex"
mage indexer:set-mode schedule || true
mage indexer:reindex

# Register the seeded media files (CMS banners etc.) in the media gallery tables
echo "== media-gallery:sync"
mage media-gallery:sync || true

echo "== cache flush"
mage cache:flush

echo "== $(date -Is) INSTALL COMPLETE"
echo "   storefront: ${MAGENTO_BASE_URL}"
echo "   admin:      ${MAGENTO_BASE_URL}${MAGENTO_ADMIN_FRONTNAME:-admin}/  (user: ${MAGENTO_ADMIN_USER})"
