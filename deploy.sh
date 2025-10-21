#!/bin/bash
set -e

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="deploy_${TIMESTAMP}.log"
DEFAULT_BRANCH="main"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Error handling
trap 'log "❌ Script failed at line $LINENO"; exit 1' ERR

# Cleanup function
cleanup() {
    log "🧹 Cleaning up deployed resources..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" <<EOF
        sudo docker ps -aq | xargs -r sudo docker rm -f
        sudo docker images -q | xargs -r sudo docker rmi -f
        sudo rm -rf ~/deploy_app
        sudo rm -f /etc/nginx/sites-available/deploy_app
        sudo rm -f /etc/nginx/sites-enabled/deploy_app
        sudo nginx -t && sudo systemctl reload nginx
EOF
    log "✅ Cleanup completed"
    exit 0
}

# Check for cleanup flag
if [ "$1" = "--cleanup" ]; then cleanup; fi

log "🚀 Starting HNG Stage 1 Automated Deployment"

# ===== 1. COLLECT PARAMETERS =====
log "📝 Collecting deployment parameters..."
read -p "Enter GitHub Repository URL: " REPO_URL
read -p "Enter GitHub Personal Access Token (PAT): " PAT
echo
read -p "Enter Branch name [default: $DEFAULT_BRANCH]: " BRANCH
BRANCH=${BRANCH:-$DEFAULT_BRANCH}
read -p "Enter Remote Server Username: " USERNAME
read -p "Enter Remote Server IP: " SERVER_IP
read -p "Enter SSH Key Path: " SSH_KEY
read -p "Enter Application Port: " APP_PORT

# Validate inputs
if [ -z "$REPO_URL" ] || [ -z "$PAT" ] || [ -z "$USERNAME" ] || [ -z "$SERVER_IP" ] || [ -z "$SSH_KEY" ] || [ -z "$APP_PORT" ]; then
    log "❌ Missing required parameters"
    exit 1
fi

# ===== 2. CLONE REPOSITORY =====
REPO_NAME=$(basename "$REPO_URL" .git)
log "📥 Cloning repository: $REPO_NAME"

if [ -d "$REPO_NAME" ]; then
    log "🔄 Repository exists - pulling updates"
    cd "$REPO_NAME"
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
else
    AUTH_URL="https://${PAT}@${REPO_URL#https://}"
    git clone -b "$BRANCH" "$AUTH_URL" "$REPO_NAME"
    cd "$REPO_NAME"
fi
log "✅ Repository ready on branch: $BRANCH"

# ===== 3. VERIFY DOCKER FILES =====
log "🔍 Checking for Docker configuration..."
if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    log "✅ Docker configuration found"
else
    log "❌ No Dockerfile or docker-compose.yml found"
    exit 1
fi

# ===== 4. SSH CONNECTION CHECK =====
log "🔌 Testing SSH connection..."
ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "$USERNAME@$SERVER_IP" "echo '✅ SSH connection successful'" || {
    log "❌ SSH connection failed"
    exit 1
}

# ===== 5. PREPARE REMOTE ENVIRONMENT =====
log "⚙️ Preparing remote server environment..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" <<EOF
    set -e
    sudo apt update -y
    sudo apt install -y docker.io docker-compose nginx curl
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo systemctl enable nginx
    sudo systemctl start nginx
    sudo usermod -aG docker "\$USER" || true
    docker --version && docker-compose --version && nginx -v
EOF
log "✅ Remote environment prepared"

# ===== 6. DEPLOY DOCKERIZED APPLICATION =====
log "🐳 Deploying application..."
log "📤 Transferring files to remote server..."
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    --exclude '.git' --exclude 'node_modules' \
    ./ "$USERNAME@$SERVER_IP:~/deploy_app/"

log "🔨 Building and running containers..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" <<EOF
    set -e
    cd ~/deploy_app
    
    # Stop existing containers
    sudo docker ps -aq | xargs -r sudo docker rm -f
    
    # Deploy based on configuration
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        sudo docker-compose up -d --build
    else
        sudo docker build -t deploy_app .
        sudo docker run -d -p $APP_PORT:$APP_PORT --name deploy_app deploy_app
    fi
    
    # Validate container
    sleep 5
    sudo docker ps --filter "name=deploy_app" --format "table {{.Names}}\t{{.Status}}"
    
    # Test application
    if curl -s -f http://localhost:$APP_PORT > /dev/null; then
        echo "✅ Application running on port $APP_PORT"
    else
        echo "❌ Application not responding"
        exit 1
    fi
EOF
log "✅ Application deployed successfully"

# ===== 7. CONFIGURE NGINX REVERSE PROXY =====
log "🌐 Configuring Nginx reverse proxy..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" <<EOF
    set -e
    sudo bash -c 'cat > /etc/nginx/sites-available/deploy_app <<NGINXCFG
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
    }
}
NGINXCFG'
    sudo ln -sf /etc/nginx/sites-available/deploy_app /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t && sudo systemctl reload nginx
EOF
log "✅ Nginx reverse proxy configured"

# ===== 8. VALIDATE DEPLOYMENT =====
log "✅ Validating deployment..."
sleep 3

# Test internally
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" \
    "curl -s -f http://localhost:$APP_PORT > /dev/null"; then
    log "✅ Application accessible internally"
else
    log "⚠️ Application not responding internally"
fi

# Test Nginx
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" \
    "curl -s -f http://localhost > /dev/null"; then
    log "✅ Nginx proxy working"
else
    log "⚠️ Nginx not responding"
fi

# Test externally
log "🌍 Testing external access..."
if curl -s -f --max-time 10 "http://$SERVER_IP/" > /dev/null; then
    log "🎉 SUCCESS: Application accessible at http://$SERVER_IP"
else
    log "⚠️ External test failed - check security groups"
fi

log "🏁 Deployment completed successfully!"
log "📋 Log file: $LOGFILE"
log "🔧 Cleanup: ./deploy.sh --cleanup"
