# EC2 Docker Deployment Plan (Two Services, No Public Access)
Problem
You want gocortexbrokenbank deployed on AWS using plain EC2 + Docker, running both the Flask (8888) and Tomcat (9999) services, with no public exposure. You also want to execute in small, independent steps to surface issues early.
## Current State (Repo)
* Repo contains Dockerfile (Flask, port 8888) and Dockerfile.BrokenBank/Tomcat resources (Tomcat, 8080). A basic docker-compose.yml exists for the Flask service only.
## Approach
Use a single EC2 instance running Docker and docker compose. Images are built in GitHub Actions and pushed to Amazon ECR via GitHub OIDC. Deployment is triggered from Actions using SSM RunCommand to pull latest images and restart containers on the instance. No inbound security group rules are opened; access is via SSM Session Manager port forwarding only. Start simple, then iterate.
## Networking Options
* QuickStart (recommended first): Public subnet, instance has public IP but Security Group has 0 inbound rules; access only via SSM. Outbound internet via public gateway for package installs and ECR pulls.
* Strict Private (later): Private subnet, no public IP, NAT Gateway (or VPC Endpoints for SSM/ECR/S3). More setup, higher cost/complexity.
## Step-by-Step Plan (run sequentially)
### Step 1: Repo Prep (local only)
* Add compose file supporting both services without host port exposure by default and a variant for EC2 that binds 127.0.0.1 only.
* Paths to add:
    * infra/docker/docker-compose.base.yml
    * infra/docker/docker-compose.ec2.yml
    * infra/scripts/deploy.sh (idempotent: docker compose pull && up -d)
* Keep existing Dockerfiles; add minor build args if needed.
## Step 2: GitHub OIDC + IAM (one-time)
* Create IAM role assumed by GitHub Actions with minimal permissions: ECR push/pull, SSM SendCommand, EC2 DescribeInstances, CloudWatch Logs:Put if needed.
* Variables to add in repo Settings > Variables: AWS_ACCOUNT_ID, AWS_REGION, AWS_ROLE_ARN, ECR_REPO_PY=broken-bank-py, ECR_REPO_JAVA=broken-bank-java, EC2_INSTANCE_ID (or SSM target tag key/value).
## Step 3: ECR Setup (one-time)
* Create two ECR repositories: broken-bank-py and broken-bank-java.
* Optionally enable image scanning on push.
## Step 4: EC2 Provisioning (one-time)
* Launch t3.small or t3.medium, Amazon Linux 2023.
* Attach Instance Profile with: AmazonSSMManagedInstanceCore + custom policy for ECR pull.
* Security Group: no inbound rules, allow all outbound.
* User data bootstraps Docker, docker compose plugin, enables SSM, and writes compose files under /opt/brokenbank.
* Files added in repo for reuse:
    * infra/ec2/user-data.sh
    * infra/ec2/instance-policy.json (ECR pull permissions)
## Step 5: Build Pipeline (GitHub Actions)
* Workflow .github/workflows/build.yml builds two images and pushes to ECR on push to main and manual dispatch.
* Tag images with SHA and :latest.
## Step 6: Deploy Pipeline (GitHub Actions)
* Workflow .github/workflows/deploy-ec2.yml authenticates via OIDC, then uses aws ssm send-command to the instance:
    * export image tags
    * docker login to ECR
    * docker compose -f /opt/brokenbank/docker-compose.ec2.yml pull && up -d
* Safe, idempotent, no SSH keys.
## Step 7: Access and Testing (no public)
* Use AWS SSM port forwarding to test locally:
    * Forward local 8888->instance 127.0.0.1:8888 (Flask)
    * Forward local 9999->instance 127.0.0.1:9999 (Tomcat)
* Verify health endpoints.
## Step 8: Hardening/Next Iterations
* Move to Strict Private networking with NAT or VPC endpoints.
* Add CloudWatch logs for both containers.
* Add second workflow for blue/green or canary on a second instance/ASG.
## Deliverables (added to repo)
* infra/docker/docker-compose.base.yml
* infra/docker/docker-compose.ec2.yml
* infra/scripts/deploy.sh
* infra/ec2/user-data.sh
* infra/ec2/instance-policy.json
* .github/workflows/build.yml
* .github/workflows/deploy-ec2.yml
## Validation
* build.yml succeeds and pushes to ECR.
* EC2 instance joins SSM and runs docker compose up with both services.
* No inbound SG rules; only SSM access works.
* curl via SSM port forwarding returns expected responses on 8888 and 9999.
