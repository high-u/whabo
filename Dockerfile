FROM openresty/openresty:1.17.8.2-2-centos
COPY nginx.conf /etc/nginx/conf.d/app.conf
ARG DOMAIN
RUN sed -i -e "s/example.com/$DOMAIN/g" /etc/nginx/conf.d/app.conf
CMD ["/usr/bin/openresty", "-g", "daemon off;"]
