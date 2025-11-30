#!/bin/bash
# DSpace 7.6 Installation Script for Ubuntu 22.04
# Author: Jonathan Saina (adapted from Otuoma Sanya guide)
# Fully idempotent with dependency checks

set -e

echo "Starting DSpace 7.6 installation..."
echo "This script will run as sudo. You may be prompted for your password."

########################################
# VARIABLES (Modify as needed)
########################################
DS_USER="dspace"
DB_PASS="dspace"  # Change this to a strong password
DS_HOST="localhost"
JAVA_HOME="/usr/lib/jvm/java-1.11.0-openjdk-amd64"
DS_DIR="/opt/dspace/server"
CLIENT_DIR="/opt/dspace/client"

########################################
# 1. Update packages
########################################
echo "Step 1: Updating and upgrading packages (5 min)..."
sudo apt update && sudo apt upgrade -y
echo "Packages updated successfully."

########################################
# 2. Create DSpace user
########################################
echo "Step 2: Creating DSpace system user..."
if id "$DS_USER" &>/dev/null; then
    echo "User $DS_USER already exists. Skipping."
else
    sudo adduser --gecos "" $DS_USER
    sudo usermod -aG sudo $DS_USER
    echo "DSpace user setup complete."
fi

########################################
# 3. Install Java, Git, Ant, Maven
########################################
echo "Step 3: Installing Java 11, Git, Ant, Maven..."
for pkg in openjdk-11-jdk git ant maven; do
    if dpkg -s $pkg &>/dev/null; then
        echo "$pkg is already installed. Skipping."
    else
        sudo apt install -y $pkg
        echo "$pkg installed successfully."
    fi
done

########################################
# 4. PostgreSQL setup
########################################
echo "Step 4: Installing PostgreSQL 14..."
if dpkg -s postgresql-14 &>/dev/null; then
    echo "PostgreSQL 14 already installed. Skipping."
else
    sudo apt install -y postgresql postgresql-contrib libpostgresql-jdbc-java
    echo "PostgreSQL installed successfully."
fi

echo "Configuring PostgreSQL access..."
if ! grep -q "host dspace dspace 127.0.0.1/32 md5" /etc/postgresql/14/main/pg_hba.conf; then
    echo "host dspace dspace 127.0.0.1/32 md5" | sudo tee -a /etc/postgresql/14/main/pg_hba.conf
    sudo sed -i 's/ident/trust/' /etc/postgresql/14/main/pg_hba.conf
    sudo sed -i 's/md5/trust/' /etc/postgresql/14/main/pg_hba.conf
    sudo sed -i 's/peer/trust/' /etc/postgresql/14/main/pg_hba.conf
fi
sudo systemctl restart postgresql

echo "Creating DSpace database and user..."
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='dspace'")
if [ "$DB_EXISTS" = "1" ]; then
    echo "DSpace database already exists. Skipping."
else
    sudo -u postgres psql <<EOF
CREATE USER $DS_USER;
CREATE DATABASE dspace ENCODING 'UNICODE' OWNER $DS_USER;
\c dspace
CREATE EXTENSION IF NOT EXISTS pgcrypto;
ALTER ROLE $DS_USER WITH PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE dspace TO $DS_USER;
\q
EOF
fi
sudo systemctl restart postgresql
echo "PostgreSQL setup complete."

########################################
# 5. Install Solr 8
########################################
echo "Step 5: Installing Solr 8.11.4..."
if [ -d /opt/solr ]; then
    echo "Solr already installed. Skipping."
else
    wget -c https://dlcdn.apache.org/lucene/solr/8.11.4/solr-8.11.4.tgz
    tar xvf solr-8.11.4.tgz
    sudo bash solr-8.11.4/bin/install_solr_service.sh solr-8.11.4.tgz
    echo "Solr installed successfully."
fi

########################################
# 6. Setup Tomcat9
########################################
echo "Step 6: Installing Tomcat9..."
if dpkg -s tomcat9 &>/dev/null; then
    echo "Tomcat9 already installed. Skipping."
else
    sudo apt install -y tomcat9
    echo "Tomcat9 installed successfully."
fi

echo "Configuring JAVA_HOME and UTF-8 connector..."
sudo sed -i "s|#JAVA_HOME=.*|JAVA_HOME=$JAVA_HOME|" /etc/default/tomcat9
if ! grep -q 'URIEncoding="UTF-8"' /etc/tomcat9/server.xml; then
    sudo sed -i 's|</Service>|<Connector port="8080" minSpareThreads="25" enableLookups="false" address="127.0.0.1" redirectPort="8443" connectionTimeout="20000" disableUploadTimeout="true" URIEncoding="UTF-8"/>\n</Service>|' /etc/tomcat9/server.xml
fi
sudo systemctl restart tomcat9
echo "Tomcat9 setup complete."

########################################
# 7. Install DSpace Backend
########################################
echo "Step 7: Installing DSpace backend..."
if [ -d "$DS_DIR" ]; then
    echo "DSpace backend already exists. Skipping download and build."
else
    wget -c https://github.com/DSpace/DSpace/archive/refs/tags/dspace-7.6.tar.gz
    tar -zxvf dspace-7.6.tar.gz
    mv DSpace-dspace-7.6 dspace-server-src
    cd dspace-server-src

    echo "Creating deployment directory..."
    sudo mkdir -p $DS_DIR
    sudo chown $DS_USER:$DS_USER -R $DS_DIR

    echo "Copying local.cfg example..."
    cp dspace/config/local.cfg.EXAMPLE dspace/config/local.cfg
    echo "Please edit dspace/config/local.cfg to set your host and DB credentials, then press ENTER."
    read -p "Press ENTER after editing local.cfg..."

    echo "Building DSpace backend..."
    mvn package

    echo "Deploying DSpace..."
    cd dspace/target/dspace-installer
    ant fresh_install

    echo "Configuring Tomcat to serve DSpace..."
    cd /var/lib/tomcat9/webapps
    sudo ln -s $DS_DIR/webapps/server server

    echo "Copying Solr cores..."
    sudo cp -r $DS_DIR/solr/* /var/solr/data/
    sudo chown solr:solr -R /var/solr/data
    sudo systemctl restart solr

    echo "Allowing Tomcat to read/write DSpace folder..."
    sudo mkdir -p /etc/systemd/system/multi-user.target.wants/
    sudo bash -c "echo 'ReadWritePaths=$DS_DIR/' >> /etc/systemd/system/multi-user.target.wants/tomcat9.service"
    sudo systemctl daemon-reload && sudo systemctl restart tomcat9

    echo "Initializing DSpace database..."
    cd $DS_DIR
    ./bin/dspace database migrate
fi

########################################
# 8. Install DSpace Angular Frontend
########################################
echo "Step 8: Installing Angular frontend..."
if [ -d "$CLIENT_DIR/dist" ]; then
    echo "Angular frontend already exists. Skipping."
else
    wget -c https://github.com/DSpace/dspace-angular/archive/refs/tags/dspace-7.6.tar.gz
    tar -zxvf dspace-7.6.tar.gz
    mv dspace-angular-dspace-7.6 dspace-7-angular
    cd dspace-7-angular

    echo "Installing NVM, Node, NPM, Yarn, PM2..."
    command -v nvm &>/dev/null || curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.39.1/install.sh | bash
    source ~/.nvm/nvm.sh
    sudo apt install -y npm
    npm install --global yarn
    npm install -g n
    n 18
    npm install -g pm2

    echo "Installing Angular dependencies and building frontend..."
    yarn install
    yarn build:prod

    echo "Deploying Angular to $CLIENT_DIR..."
    sudo mkdir -p $CLIENT_DIR
    sudo chown $DS_USER:$DS_USER -R $CLIENT_DIR
    cp -r dist $CLIENT_DIR/
    mkdir -p $CLIENT_DIR/config
    cp config/config.example.yml $CLIENT_DIR/config/config.prod.yml

    echo "Creating PM2 process file..."
    cat <<EOF > $CLIENT_DIR/dspace-ui.json
{
    "apps": [
        {
           "name": "dspace-ui",
           "cwd": "$CLIENT_DIR",
           "script": "dist/server/main.js",
           "instances": 4,
           "exec_mode": "cluster",
           "env": {
              "NODE_ENV": "production"
           }
        }
    ]
}
EOF
    pm2 start $CLIENT_DIR/dspace-ui.json
fi

########################################
# 9. Setup Nginx Reverse Proxy
########################################
echo "Step 9: Installing Nginx..."
if dpkg -s nginx &>/dev/null; then
    echo "Nginx already installed. Skipping."
else
    sudo apt install -y nginx
fi
echo "Please edit /etc/nginx/sites-enabled/default to configure your server block for DSpace."
read -p "Press ENTER after configuring Nginx..."
sudo systemctl restart nginx
echo "Nginx restarted."

########################################
# 10. Setup SSL via Certbot
########################################
echo "Step 10: Installing Certbot..."
if snap list | grep -q certbot; then
    echo "Certbot already installed. Skipping."
else
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
fi
echo "Please run 'sudo certbot --nginx' manually to fetch SSL certificate."

########################################
# 11. Create DSpace Administrator
########################################
echo "Step 11: Creating DSpace administrator account..."
cd $DS_DIR
sudo bin/dspace create-administrator

echo "DSpace 7.6 installation complete!"
