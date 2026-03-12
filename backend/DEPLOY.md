# Venuu Backend — Deployment Guide

## Architecture

- **Amplify** → Cognito auth only (already set up)
- **SAM** → API Gateway + Lambda (TypeScript) + DynamoDB (this guide)

## Prerequisites

1. AWS CLI configured (`aws configure`)
2. SAM CLI installed (`brew install aws-sam-cli`)
3. Node.js 20+ installed
4. Amplify auth already set up (`amplify init` + `amplify add auth`)

## Step 1: Get Your Cognito User Pool ARN

```bash
# List your Cognito User Pools
aws cognito-idp list-user-pools --max-results 10 --region us-east-1

# Note the Pool ID (e.g., us-east-1_ABC123xyz)
# ARN format: arn:aws:cognito-idp:REGION:ACCOUNT_ID:userpool/POOL_ID
```

## Step 2: Install Dependencies & Build

```bash
cd backend/lambda
npm install
npm run build    # Compiles TypeScript → dist/
```

## Step 3: Deploy to DEV

```bash
cd backend   # (parent of lambda/)
sam build
sam deploy --guided
```

During guided deploy, enter:
- **Stack name**: `venuu-backend-dev`
- **Region**: `us-east-1` (same as Amplify)
- **CognitoUserPoolArn**: paste the ARN from Step 1
- **Stage**: `dev` (default)
- Accept defaults for everything else

SAM will output your API URL:
```
https://abc123.execute-api.us-east-1.amazonaws.com/dev
```

## Step 4: Update the iOS App

In `Venuu/Services/APIClient.swift`, update the base URL:
```swift
private let baseURL = "https://abc123.execute-api.us-east-1.amazonaws.com/dev"
```

## Step 5: Test the API

```bash
# Get a token (use your Cognito credentials)
TOKEN="your-jwt-token"

# Test: get profile
curl -H "Authorization: $TOKEN" \
  https://abc123.execute-api.us-east-1.amazonaws.com/dev/user/profile

# Test: submit a report
curl -X POST \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"venueId":"test_1","busynessLevel":3,"venueName":"Test Bar","venueType":"bar","lat":40.7128,"lng":-74.006}' \
  https://abc123.execute-api.us-east-1.amazonaws.com/dev/reports

# Test: get nearby reports
curl -H "Authorization: $TOKEN" \
  "https://abc123.execute-api.us-east-1.amazonaws.com/dev/reports?lat=40.7128&lng=-74.006&radius=2000"
```

## Promoting to Production

When dev is tested and ready:

```bash
sam deploy \
  --stack-name venuu-backend-prod \
  --parameter-overrides Stage=prod CognitoUserPoolArn=arn:aws:... \
  --no-confirm-changeset
```

This creates separate DynamoDB tables (`VenueReports-prod`, `UserProfiles-prod`) and a separate API Gateway stage.

Update `APIClient.swift` to point to the prod URL when shipping.

## Cost Estimate (Dev)

| Service | Free Tier | Estimated Cost |
|---------|-----------|---------------|
| Lambda | 1M requests/mo free | $0 |
| API Gateway | 1M calls/mo free | $0 |
| DynamoDB | 25 WCU + 25 RCU free | $0 |

**Total for dev/testing: $0** (well within free tier)

## Useful Commands

```bash
# View logs for a function
sam logs -n SubmitReportFunction --stack-name venuu-backend-dev --tail

# Delete the dev stack
sam delete --stack-name venuu-backend-dev

# Redeploy after code changes
cd lambda && npm run build && cd .. && sam build && sam deploy
```
