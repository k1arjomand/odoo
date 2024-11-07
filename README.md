Odoo Deployment with Docker Swarm
This repository contains scripts and configuration files for deploying Odoo using Docker Swarm. The setup includes Odoo as the application and PostgreSQL as its database, utilizing Docker secrets for secure database password management.

Features
Secure Deployment: Uses Docker secrets to manage sensitive data like the PostgreSQL password.
Modular Architecture: Includes separate services for Odoo and PostgreSQL.
Scalable: Designed to work seamlessly with Docker Swarm for scaling up services.
Persistent Data: Uses Docker volumes to ensure data is not lost during container restarts.
Ease of Use: Includes a ready-to-use docker-compose.yml file for quick deployment.

all you to have odoo, is to run the test.sh

to config odoo u can change ./config/odoo.conf

it will check dependencies 
