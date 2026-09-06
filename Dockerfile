FROM ghcr.io/sesamesesamum/example_k8s:latest

USER root

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/index.html /usr/share/nginx/html/index.html

RUN chown -R nginx:nginx /usr/share/nginx/html

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD wget --quiet --tries=1 --spider http://127.0.0.1:8080/ || exit 1