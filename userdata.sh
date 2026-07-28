#!/bin/bash

set -Eeuo pipefail
exec > >(tee -a /var/log/devcloud-userdata.log) 2>&1

printf '%s\n' '${environment_name}' >/etc/devcloud-environment
hostnamectl set-hostname 'devcloud-${environment_name}' || true

###########################################
# Update System
###########################################

apt-get update -y

###########################################
# Install Docker & Docker Compose
###########################################

apt-get install -y docker.io docker-compose-v2

systemctl enable docker
systemctl start docker

# Google OS Login creates administrator accounts dynamically. Administrators
# should use `sudo docker ...`; do not assume that a local `ubuntu` user exists.

###########################################
# Create Docker Compose Directory
###########################################

mkdir -p /opt/runtime
mkdir -p /opt/runtime/webxr

###########################################
# Create docker-compose.yml
###########################################

cat <<'COMPOSE_EOF' >/opt/runtime/docker-compose.yml
services:

  #################################
  # Runtime Containers
  #################################

  python:
    image: python:3.12
    container_name: python-runtime
    command: sleep infinity
    restart: unless-stopped

  node:
    image: node:22
    container_name: node-runtime
    command: sleep infinity
    restart: unless-stopped

  java:
    image: eclipse-temurin:21
    container_name: java-runtime
    command: sleep infinity
    restart: unless-stopped

  golang:
    image: golang:1.22
    container_name: go-runtime
    command: sleep infinity
    restart: unless-stopped

  ruby:
    image: ruby:3.3
    container_name: ruby-runtime
    command: sleep infinity
    restart: unless-stopped

  #################################
  # Framework Containers
  #################################

  django:
    image: khalidale/django-framework:latest
    container_name: django-framework
    restart: unless-stopped

  flask:
    image: khalidale/flask-framework:latest
    container_name: flask-framework
    restart: unless-stopped

  fastapi:
    image: khalidale/fastapi-framework:latest
    container_name: fastapi-framework
    restart: unless-stopped

  express:
    image: khalidale/express-framework:latest
    container_name: express-framework
    restart: unless-stopped

  springboot:
    image: khalidale/springboot-framework:latest
    container_name: springboot-framework
    restart: unless-stopped

  dotnet:
    image: mcr.microsoft.com/dotnet/sdk:8.0
    container_name: dotnet-framework
    command: sleep infinity
    restart: unless-stopped

  spark:
    image: apache/spark:latest
    container_name: spark-framework
    command: sleep infinity
    restart: unless-stopped

  #################################
  # Database Containers
  #################################

  mysql:
    image: mysql:8.4
    container_name: mysql-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${jsonencode(mysql_root_password)}
      MYSQL_DATABASE: ${jsonencode(mysql_database)}
      MYSQL_USER: ${jsonencode(mysql_user)}
      MYSQL_PASSWORD: ${jsonencode(mysql_password)}
        
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql

  mariadb:
    image: mariadb:11
    container_name: mariadb-db
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${jsonencode(mariadb_root_password)}
      MARIADB_DATABASE: ${jsonencode(mariadb_database)}
      MARIADB_USER: ${jsonencode(mariadb_user)}
      MARIADB_PASSWORD: ${jsonencode(mariadb_password)}
    ports:
      - "3307:3306"
    volumes:
      - mariadb_data:/var/lib/mysql

  postgres:
    image: postgres:17
    container_name: postgres-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${jsonencode(postgres_user)}
      POSTGRES_PASSWORD: ${jsonencode(postgres_password)}
      POSTGRES_DB: ${jsonencode(postgres_database)}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  mongodb:
    image: mongo:8
    container_name: mongodb
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${jsonencode(mongodb_user)}
      MONGO_INITDB_ROOT_PASSWORD: ${jsonencode(mongodb_password)}
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db

  redis:
    image: redis:8
    container_name: redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  #################################
  # Web Server Containers
  #################################

  nginx:
    image: nginx:latest
    container_name: nginx-server
    restart: unless-stopped
    ports:
      - "8080:80"

  httpd:
    image: httpd:2.4
    container_name: apache-server
    restart: unless-stopped
    ports:
      - "8081:80"

  tomcat:
    image: tomcat:11-jdk21
    container_name: tomcat-server
    restart: unless-stopped
    ports:
      - "8082:8080"

  wildfly:
    image: quay.io/wildfly/wildfly:latest
    container_name: wildfly-server
    restart: unless-stopped
    ports:
      - "8083:8080"

  #################################
  # AI Chatbot
  #################################

  chatbot:
    image: ghcr.io/open-webui/open-webui:main
    container_name: chatbot
    restart: unless-stopped

    ports:
      - "3000:8080"

    volumes:
      - openwebui_data:/app/backend/data    




  jupyter:
    image: quay.io/jupyter/base-notebook:latest
    container_name: jupyter-notebook
    restart: unless-stopped
    ports:
      - "8888:8888"
    environment:
      JUPYTER_TOKEN: ${jsonencode(jupyter_token)}
    volumes:
      - jupyter_data:/home/jovyan/work


  #################################
  # Blockchain Containers
  #################################

  blockchain:
    image: trufflesuite/ganache:latest
    container_name: blockchain
    restart: unless-stopped

    ports:
      - "8545:8545"

  remix:
    image: remixproject/remix-ide:latest
    container_name: blockchain-remix
    restart: unless-stopped

    ports:
      - "8085:80"    

  #################################
  # IoT Platform
  #################################

  emqx:
    image: emqx/emqx:latest
    container_name: emqx
    restart: unless-stopped

    ports:
      - "1883:1883"
      - "18083:18083"    

  #################################
  # Metaverse
  #################################

  webxr:
    image: nginx:latest
    container_name: webxr
    restart: unless-stopped

    ports:
      - "8090:80"

    volumes:
      - /opt/runtime/webxr:/usr/share/nginx/html:ro    

  #################################
  # Backend as a Service
  #################################

  pocketbase:
    image: spectado/pocketbase:latest
    container_name: pocketbase
    restart: unless-stopped

    ports:
      - "8091:8090"

    volumes:
      - pocketbase_data:/pb_data    

  #################################
  # Container Management
  #################################

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped

    ports:
      - "9000:9000"

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data    


  #################################
  # Robotic Process Automation (n8n)
  #################################

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped

    ports:
      - "5678:5678"

    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http

    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  jupyter_data:
  mysql_data:
  mariadb_data:
  postgres_data:
  mongodb_data:
  redis_data:
  openwebui_data:
  pocketbase_data:
  portainer_data:
  n8n_data:
COMPOSE_EOF
chmod 0600 /opt/runtime/docker-compose.yml
cat <<'EOF' >/opt/runtime/webxr/index.html
${webxr_index}
EOF
cd /opt/runtime
docker compose pull
docker compose up -d

echo "========================================="
echo "Runtime Containers Ready"
echo "Framework Containers Ready"
echo "Database Containers Ready"
echo "Web Server Containers Ready"
echo "AI/ML Containers Ready"
echo "========================================="
