# syntax=docker/dockerfile:1
FROM nginx:1.27-alpine

# Static page and the templated reverse-proxy config.
COPY index.html /usr/share/nginx/html/index.html
COPY default.conf.template /etc/nginx/templates/default.conf.template

# Defaults; overridden by the Helm chart via env.
# NGINX_ENTRYPOINT_LOCAL_RESOLVERS makes the entrypoint export
# NGINX_LOCAL_RESOLVERS (from /etc/resolv.conf) for the config template.
ENV BACKEND_HOST=backend \
    BACKEND_PORT=80 \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1

EXPOSE 80
