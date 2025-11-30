# DSpace 7.6 Installation Script for Ubuntu 22.04

This script automates the installation of **DSpace 7.6** on Ubuntu 22.04, including:

- PostgreSQL 14 setup
- Solr 8 installation
- Tomcat 9 configuration
- DSpace backend deployment
- DSpace Angular frontend deployment with PM2
- Nginx reverse proxy setup
- SSL setup guidance using Certbot
- Creating a DSpace administrator account

---

## What the Script Does

1. Updates and upgrades system packages.
2. Creates a `dspace` system user and adds it to sudoers.
3. Installs Java 11, Git, Ant, Maven, Node.js, NPM, Yarn, and PM2.
4. Installs and configures PostgreSQL database and user for DSpace.
5. Downloads and installs Solr 8.
6. Installs and configures Tomcat9 with proper memory and UTF-8 connector.
7. Downloads, builds, and deploys the DSpace backend.
8. Downloads, builds, and deploys the DSpace Angular frontend.
9. Configures Nginx as a reverse proxy (requires manual configuration of server block).
10. Provides guidance to set up SSL with Certbot.
11. Initializes DSpace database and creates an administrator account.

The script echoes **progress messages, estimated times for each step, and success messages** to guide you through the process.

---

## How to Create the Script File

You can download and run the DSpace 7.6 installation script directly from GitHub:

1. **Download the script**
Download the script to your home directory
```bash
cd
wget https://github.com/DSpace-7.6-Installation-on-Ubuntu-22.04/install-dspace.sh
chmod +x install-dspace.sh
sudo ./install-dspace.sh
