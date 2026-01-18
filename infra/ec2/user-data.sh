#!/bin/bash
set -e

# User data script for GoCortex Broken Bank EC2 instance
# Amazon Linux 2023 - Installs Docker, Docker Compose, SSM Agent

# Update system
dnf update -y

# Install Docker
dnf install -y docker
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install Docker Compose plugin
DOCKER_CONFIG=${DOCKER_CONFIG:-/usr/local/lib/docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

# Verify Docker Compose
docker compose version

# Create application directory
mkdir -p /opt/brokenbank/instance
chmod -R 755 /opt/brokenbank

# Create docker-compose.yml for EC2 deployment
cat > /opt/brokenbank/docker-compose.yml <<'EOF'
services:
  gocortex-broken-bank:
    image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG:-latest}
    container_name: gocortex-broken-bank
    restart: unless-stopped
    ports:
      - "127.0.0.1:8888:8888"
      - "127.0.0.1:8080:8080"
    environment:
      - SESSION_SECRET=${SESSION_SECRET:-hardcoded-docker-secret-key}
      - DATABASE_URL=sqlite:///app/instance/gocortexbrokenbank.db
      - FLASK_ENV=production
      - LOCALE=${LOCALE:-en}
    volumes:
      - /opt/brokenbank/instance:/app/instance
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8888/", "&&", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 3s
      start_period: 10s
      retries: 3
EOF

# Create deployment script
cat > /opt/brokenbank/deploy.sh <<'EOF'
#!/bin/bash
set -e

# GoCortex Broken Bank - Deployment Script
# Pulls latest image from ECR and restarts container

cd /opt/brokenbank

# Get AWS region from instance metadata
export AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REPO=${ECR_REPO:-gocortex-broken-bank}
export IMAGE_TAG=${IMAGE_TAG:-latest}

echo "Deploying GoCortex Broken Bank..."
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo "Image: $ECR_REPO:$IMAGE_TAG"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Pull and restart
docker compose pull
docker compose up -d

echo "Deployment complete!"
docker compose ps
EOF

chmod +x /opt/brokenbank/deploy.sh

# Install AWS CLI v2 (if not present)
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Ensure SSM Agent is running (pre-installed on AL2023)
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

echo "EC2 instance bootstrap complete!"
