#!/bin/bash

# Function to check if a program is installed
check_installed() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    sudo apt update
    sudo apt install -y nginx docker.io docker-compose net-tools lsof
    sudo systemctl enable nginx docker
    sudo systemctl start nginx docker
    echo "Dependencies installed."
}

# Check dependencies
missing_dependencies=()
if ! check_installed "nginx"; then
    missing_dependencies+=("nginx")
fi
if ! check_installed "docker"; then
    missing_dependencies+=("docker")
fi
if ! check_installed "docker-compose"; then
    missing_dependencies+=("docker-compose")
fi

if [ ${#missing_dependencies[@]} -ne 0 ]; then
    echo "The following dependencies are missing: ${missing_dependencies[*]}"
    read -p "Do you want to install them? (yes/no): " response
    if [[ "$response" == "yes" || "$response" == "y" ]]; then
        install_dependencies
    else
        echo "Cannot proceed without installing dependencies. Exiting."
        exit 1
    fi
fi

# Ensure Docker Swarm is initialized
if ! docker info | grep -q "Swarm: active"; then
    echo "Initializing Docker Swarm..."
    docker swarm init
    if [ $? -ne 0 ]; then
        echo "Failed to initialize Docker Swarm. Exiting."
        exit 1
    fi
    echo "Docker Swarm initialized successfully."
fi

# Check if the desired port is in use
read -p "Do you want to use HTTP (80) or HTTPS (443)? (http/https): " protocol
if [[ "$protocol" == "https" ]]; then
    port=443
else
    port=80
fi

if sudo lsof -i :$port | grep LISTEN; then
    echo "Port $port is currently in use."
    site_in_use=$(grep -rl "listen.*$port" /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null)
    if [ -n "$site_in_use" ]; then
        echo "The following site is using port $port: $site_in_use"
        read -p "Do you want to delete this configuration to continue? (yes/no): " response
        if [[ "$response" == "yes" ]]; then
            for site in $site_in_use; do
                if [ -L "/etc/nginx/sites-enabled/$(basename "$site")" ]; then
                    sudo rm -f "/etc/nginx/sites-enabled/$(basename "$site")"
                fi
                sudo rm -f "$site"
            done
            echo "Configuration deleted. Continuing..."
        else
            echo "Cannot proceed with port conflict. Exiting."
            exit 1
        fi
    fi
fi

# Create NGINX configuration
echo "Configuring NGINX..."
read -p "Enter your domain or IP for the NGINX server_name: " domain

if [[ "$protocol" == "https" ]]; then
    read -p "Enter the path to your SSL certificate: " ssl_cert
    read -p "Enter the path to your SSL private key: " ssl_key
    listen_directive="listen 443 ssl;\n    ssl_certificate $ssl_cert;\n    ssl_certificate_key $ssl_key;"
else
    listen_directive="listen 80;"
fi

nginx_config="/etc/nginx/sites-available/$domain"
cat <<EOF > $nginx_config
server {
    $listen_directive
    server_name $domain;

    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_pass http://localhost:8069;
    }
}
EOF

# Enable the configuration and restart NGINX
sudo ln -s $nginx_config /etc/nginx/sites-enabled/
sudo nginx -t
if [ $? -eq 0 ]; then
    sudo systemctl restart nginx
    echo "NGINX has been configured and restarted successfully."
else
    echo "NGINX configuration error. Please check the configuration."
    exit 1
fi

# Create Docker secret for PostgreSQL password
echo "Creating Docker secret for PostgreSQL password..."
read -sp "Enter a password for PostgreSQL: " pg_password
echo "$pg_password" | docker secret create postgres_password -
if [ $? -ne 0 ]; then
    echo "Failed to create Docker secret. Exiting."
    exit 1
fi
echo "Docker secret created successfully."

# Create Docker Compose configuration
echo "Setting up Odoo with Docker Compose and secrets..."

cat <<EOF > docker-compose.yml
version: '3.1'
services:
  web:
    image: odoo:17.0
    depends_on:
      - db
    ports:
      - "8069:8069"
    volumes:
      - odoo-web-data:/var/lib/odoo
      - ./config/odoo.conf:/etc/odoo/odoo.conf
    environment:
      - PASSWORD_FILE=/run/secrets/postgres_password
    secrets:
      - postgres_password
  db:
    image: postgres:15
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
      - POSTGRES_USER=odoo
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - odoo-db-data:/var/lib/postgresql/data/pgdata
    secrets:
      - postgres_password
volumes:
  odoo-web-data:
  odoo-db-data:

secrets:
  postgres_password:
    external: true
EOF

# Run Docker Compose
docker stack deploy --compose-file docker-compose.yml odoo_stack
if [ $? -eq 0 ]; then
    echo "Odoo and PostgreSQL have been set up successfully using Docker Compose and Docker Secrets."
    echo "Access Odoo at http://$domain."
else
    echo "Failed to set up Odoo. Please check Docker Compose logs."
    exit 1
fi

