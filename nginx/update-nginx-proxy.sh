#!/bin/bash

sleep 15

GRAFANA_IP=$(docker inspect grafana | grep '"IPAddress"' | tail -1 | tr -d ' ",' | cut -d: -f2)
ZABBIX_IP=$(docker inspect zabbix-frontend | grep '"IPAddress"' | tail -1 | tr -d ' ",' | cut -d: -f2)

cat > /etc/nginx/conf.d/monitoring.conf << NGINX
server {
    listen 80;
    server_name grafana.lab.local;
    location / {
        proxy_pass http://$GRAFANA_IP:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
server {
    listen 80;
    server_name zabbix.lab.local;
    location / {
        proxy_pass http://$ZABBIX_IP:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX

nginx -t && systemctl restart nginx
