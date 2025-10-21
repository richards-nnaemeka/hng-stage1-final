# HNG DevOps Intern Stage 1 - Automated Deployment Script

A production-grade Bash script that automates the deployment of Dockerized applications to remote Linux servers with comprehensive error handling, logging, and idempotent operations.

## 🚀 Features
- **Automated Deployment**: Full CI/CD pipeline simulation
- **Docker Support**: Built-in Docker and Docker Compose support  
- **Nginx Reverse Proxy**: Automatic reverse proxy configuration
- **Comprehensive Logging**: Detailed timestamped logging
- **Error Handling**: Robust error handling with meaningful exit codes
- **Idempotent Operations**: Safe to run multiple times
- **Cleanup Functionality**: Complete resource cleanup option

## 📋 Prerequisites
**Local Machine**
- Bash 4.0+
- Git
- SSH client
- SCP (for file transfer)

**Remote Server**
- Ubuntu/Debian Linux
- SSH access with key-based authentication
- Sudo privileges for deployment user

## 🛠️ Usage
```bash
# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh

# Remove all deployed resources
./deploy.sh --cleanup
