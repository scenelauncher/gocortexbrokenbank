# GitHub OIDC + IAM Setup

This directory contains IAM configurations for GitHub Actions to deploy GoCortex Broken Bank to EC2 via OIDC federation.

## Quick Setup

### 1. Deploy CloudFormation Stack

```bash
aws cloudformation create-stack \
  --stack-name gocortex-brokenbank-github-oidc \
  --template-body file://infra/iam/github-oidc-stack.yaml \
  --parameters \
    ParameterKey=GitHubOrg,ParameterValue=scenelauncher \
    ParameterKey=GitHubRepo,ParameterValue=gocortexbrokenbank \
    ParameterKey=GitHubBranch,ParameterValue=main \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

**Note:** Replace `scenelauncher` with your GitHub organization/username and adjust region as needed.

### 2. Wait for Stack Creation

```bash
aws cloudformation wait stack-create-complete \
  --stack-name gocortex-brokenbank-github-oidc \
  --region us-east-1
```

### 3. Get Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name gocortex-brokenbank-github-oidc \
  --query 'Stacks[0].Outputs' \
  --region us-east-1
```

Save the following values:
- `GitHubActionsRoleArn` - Use this for `AWS_ROLE_ARN` in GitHub secrets

### 4. Configure GitHub Repository Variables

Go to your GitHub repository: **Settings → Secrets and variables → Actions → Variables**

Add the following **Repository Variables**:

| Variable Name | Value | Example |
|--------------|-------|---------|
| `AWS_ACCOUNT_ID` | Your AWS account ID | `123456789012` |
| `AWS_REGION` | AWS region for ECR/EC2 | `us-east-1` |
| `AWS_ROLE_ARN` | IAM role ARN from stack outputs | `arn:aws:iam::123456789012:role/GitHubActions-GoCortexBrokenBank` |
| `ECR_REPO` | ECR repository name | `gocortex-broken-bank` |
| `EC2_INSTANCE_ID` | EC2 instance ID (add after Step 4) | `i-0123456789abcdef0` |

**Note:** Use Variables (not Secrets) for non-sensitive values like account ID and region.

## Alternative: Manual IAM Setup

If you prefer not to use CloudFormation:

### 1. Create OIDC Provider (if not exists)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd
```

### 2. Create IAM Policy

```bash
aws iam create-policy \
  --policy-name GitHubActions-GoCortexBrokenBank-Policy \
  --policy-document file://infra/iam/github-actions-policy.json
```

### 3. Create IAM Role with Trust Policy

Create `trust-policy.json`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Then create the role:
```bash
aws iam create-role \
  --role-name GitHubActions-GoCortexBrokenBank \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name GitHubActions-GoCortexBrokenBank \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActions-GoCortexBrokenBank-Policy
```

## Permissions Explained

The IAM policy grants minimal permissions:

- **ECR**: Push/pull Docker images
- **SSM**: Send commands to EC2 instances tagged with `Project=gocortex-broken-bank`
- **EC2**: Describe instances (read-only)
- **CloudWatch Logs**: Write deployment logs

## Security Notes

- OIDC trust is scoped to specific GitHub repo and branch
- SSM commands only work on tagged EC2 instances
- No broad permissions granted
- Session duration limited to 1 hour
- No long-lived credentials stored in GitHub

## Troubleshooting

### "No OIDC provider found"
The OIDC provider might already exist. List providers:
```bash
aws iam list-open-id-connect-providers
```

### "Access denied" during deployment
Ensure the EC2 instance has the tag: `Project=gocortex-broken-bank`

### Role assumption fails
Verify the trust policy matches your GitHub org/repo exactly.
