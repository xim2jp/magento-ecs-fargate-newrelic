#!/bin/bash
# Magento cron loop for the "cron" ECS service (runs as www-data).
# cron:run also spawns the message-queue consumers (cron_consumers_runner in env.php).
: "${MAGE_ROOT:=/var/www/magento}"
cd "$MAGE_ROOT"

echo "[cron] loop started $(date -Is)"
while true; do
  php bin/magento cron:run 2>&1 | grep -v '^Ran jobs by schedule' || true
  sleep 60
done
