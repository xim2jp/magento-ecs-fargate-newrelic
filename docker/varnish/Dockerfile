# syntax=docker/dockerfile:1.7
#
# Varnish full-page cache for Magento. The VCL is generated from the template that
# ships with the Magento version inside the application image, so the two never drift.
ARG MAGENTO_IMAGE
FROM ${MAGENTO_IMAGE} AS magento

FROM varnish:8.0
USER root
COPY --from=magento /var/www/magento/vendor/magento/module-page-cache/etc/varnish6.vcl /tmp/varnish6.vcl
# Same substitutions as `bin/magento varnish:vcl:generate`:
#   backend nginx 127.0.0.1:8080 (same Fargate task), purge allowed from localhost (php container),
#   SSL offloaded header X-Forwarded-Proto (ALB), grace 300s.
RUN sed \
      -e 's#/\* {{ host }} \*/#127.0.0.1#g' \
      -e 's#/\* {{ port }} \*/#8080#g' \
      -e 's#/\* {{ ips }} \*/#    "127.0.0.1";#g' \
      -e 's#/\* {{ ssl_offloaded_header }} \*/#X-Forwarded-Proto#g' \
      -e 's#/\* {{ grace_period }} \*/#300#g' \
      -e 's#/\* {{ design_exceptions_code }} \*/##g' \
      /tmp/varnish6.vcl > /etc/varnish/default.vcl \
 && rm -f /tmp/varnish6.vcl \
 && varnishd -C -f /etc/varnish/default.vcl > /dev/null
# Stay root: on Fargate the non-root "varnish" user cannot bind :80 (file capabilities are
# not honoured). varnishd itself drops the worker process to an unprivileged user (-j unix).
