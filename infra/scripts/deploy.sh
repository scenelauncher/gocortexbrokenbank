#!/bin/bash
set -euo pipefail

# GoCortex Broken Bank - EC2 Deployment Script
# Idempotent deployment using Docker Compose
# Usage: ./deploy.sh [IMAGE_TAG]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/opt/brokenbank"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.ec2.yml"

# Default to latest if no tag provided
IMAGE_TAG="${1:-latest}"

echo "==> GoCortex Broken Bank Deployment"
echo "==> Image Tag: ${IMAGE_TAG}"
echo "==> Compose File: ${COMPOSE_FILE}"

# Ensure we're in the correct directory
cd "${PROJECT_ROOT}"

# Check if compose file exists
if [ ! -f "${COMPOSE_FILE}" ]; then
    echo "ERROR: Compose file not found at ${COMPOSE_FILE}"
    exit 1
fi

# Export environment variables for compose file
export IMAGE_TAG="${IMAGE_TAG}"

# Authenticate to ECR if AWS credentials are available
if command -v aws &> /dev/null && [ -n "${AWS_REGION:-}" ] && [ -n "${AWS_ACCOUNT_ID:-}" ]; then
    echo "==> Authenticating to ECR..."
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" || {
        echo "ERROR: ECR authentication failed"
        exit 1
    }
else
    echo "WARNING: AWS CLI not configured or environment variables missing - skipping ECR login"
fi

# Pull latest images
echo "==> Pulling latest image..."
docker compose -f "${COMPOSE_FILE}" pull || {
    echo "ERROR: Failed to pull image"
    exit 1
}

# Stop and remove existing containers (if any)
echo "==> Stopping existing containers..."
docker compose -f "${COMPOSE_FILE}" down || true

# Start services
echo "==> Starting services..."
docker compose -f "${COMPOSE_FILE}" up -d || {
    echo "ERROR: Failed to start services"
    exit 1
}

# Wait for health check
echo "==> Waiting for services to be healthy..."
sleep 5

# Check container status
CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' gocortex-broken-bank 2>/dev/null || echo "not_found")
if [ "${CONTAINER_STATUS}" != "running" ]; then
    echo "ERROR: Container is not running (status: ${CONTAINER_STATUS})"
    docker compose -f "${COMPOSE_FILE}" logs --tail=50
    exit 1
fi

echo "==> Deployment successful!"
echo "==> Container Status:"
docker compose -f "${COMPOSE_FILE}" ps

echo ""
echo "==> Access via SSM Port Forwarding:"
echo "    Flask:  aws ssm start-session --target \$INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8888\"],\"localPortNumber\":[\"8888\"]}'"
echo "    Tomcat: aws ssm start-session --target \$INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"9999\"]}'"
