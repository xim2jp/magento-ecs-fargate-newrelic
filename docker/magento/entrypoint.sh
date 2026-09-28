#!/bin/bash
# Container entrypoint. Roles (first argument):
#   php-fpm  - web application server (default)
#   cron     - Magento cron loop
#   install  - one-off setup:install / setup:upgrade task
#   anything else is exec'd as-is (e.g. "nginx -g 'daemon off;'")
set -euo pipefail

: "${MAGE_ROOT:=/var/www/magento}"
NR_INI=/usr/local/etc/php/conf.d/zz-newrelic.ini

configure_newrelic() {
  if [ "${NEW_RELIC_ENABLED:-false}" = "true" ] && [ -n "${NEW_RELIC_LICENSE_KEY:-}" ] && [ "${NEW_RELIC_LICENSE_KEY}" != "disabled" ]; then
    cat > "$NR_INI" <<EOF
newrelic.enabled = true
newrelic.license = "${NEW_RELIC_LICENSE_KEY}"
newrelic.appname = "${NEW_RELIC_APP_NAME:-magento}"
newrelic.labels = "${NEW_RELIC_LABELS:-}"
newrelic.framework = "magento2"
newrelic.loglevel = "info"
newrelic.logfile = "/var/log/newrelic/php_agent.log"
newrelic.daemon.logfile = "/var/log/newrelic/newrelic-daemon.log"
newrelic.daemon.app_connect_timeout = "10s"
newrelic.daemon.start_timeout = "5s"

; distributed tracing + spans (php -> mysql / valkey / opensearch / http)
newrelic.distributed_tracing_enabled = true
newrelic.span_events_enabled = true
newrelic.transaction_tracer.enabled = true
newrelic.transaction_tracer.detail = 1
newrelic.transaction_tracer.threshold = "apdex_f"
newrelic.transaction_tracer.record_sql = "obfuscated"
newrelic.transaction_tracer.explain_enabled = true
newrelic.transaction_tracer.explain_threshold = 500
newrelic.transaction_tracer.slow_sql = true
newrelic.datastore_tracer.database_name_reporting.enabled = true
newrelic.datastore_tracer.instance_reporting.enabled = true

; errors
newrelic.error_collector.enabled = true
newrelic.error_collector.record_database_errors = true

; browser (RUM) auto-injection into HTML responses
newrelic.browser_monitoring.auto_instrument = true

; code-level metrics
newrelic.code_level_metrics.enabled = true

; logs in context: Monolog records are forwarded with trace/span ids
newrelic.application_logging.enabled = true
newrelic.application_logging.forwarding.enabled = true
newrelic.application_logging.forwarding.log_level = "INFO"
newrelic.application_logging.forwarding.max_samples_stored = 10000
newrelic.application_logging.forwarding.context_data.enabled = true
newrelic.application_logging.metrics.enabled = true
EOF
    echo "[entrypoint] New Relic APM enabled (app: ${NEW_RELIC_APP_NAME:-magento})"
  else
    echo 'newrelic.enabled = false' > "$NR_INI"
    echo "[entrypoint] New Relic APM disabled (no license key)"
  fi
}

render_env_php() {
  php /usr/local/lib/magento/render-env.php > "$MAGE_ROOT/app/etc/env.php.tmp"
  mv "$MAGE_ROOT/app/etc/env.php.tmp" "$MAGE_ROOT/app/etc/env.php"
  chown www-data:www-data "$MAGE_ROOT/app/etc/env.php"
  echo "[entrypoint] app/etc/env.php rendered (base_url=${MAGENTO_BASE_URL:-?}, db=${MAGENTO_DB_HOST:-?})"
}

case "${1:-php-fpm}" in
  php-fpm)
    configure_newrelic
    render_env_php
    exec php-fpm
    ;;
  cron)
    configure_newrelic
    render_env_php
    exec runuser -u www-data -- /usr/local/bin/magento-cron.sh
    ;;
  install)
    configure_newrelic
    exec /usr/local/bin/magento-install.sh
    ;;
  *)
    exec "$@"
    ;;
esac
