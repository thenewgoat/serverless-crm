# serverless-crm

A small CRM backend on AWS for managing clients and their accounts. Everything is
Terraform, and deploying or tearing it all down is one button in GitHub Actions.

I built this for a school project in Y3S2 at NTU, mostly to learn how the pieces of
a serverless AWS setup fit together.

## How it fits together

```
client ──▶ API Gateway (HTTP API) ──▶ Lambda (clients / accounts)
                                          │
                                          ▼
                                      RDS Proxy ──▶ Aurora PostgreSQL Serverless v2
                                          │
                                   Secrets Manager (DB credentials)
```

- **API Gateway** exposes the REST routes and forwards them to two Python Lambdas.
- **Lambdas** run inside a private VPC and talk to the database through **RDS Proxy**,
  so they don't open a fresh connection on every call.
- **Aurora PostgreSQL Serverless v2** holds the `clients` and `accounts` tables
  (see [`db/schema.sql`](db/schema.sql)).
- **Secrets Manager** stores the DB credentials, and a VPC endpoint lets the Lambdas
  reach it without a NAT gateway.
- The Lambdas check a **Cognito** token and only let users in the `ITSAagent` group through.

## Routes

| Method | Path                   | What it does        |
| ------ | ---------------------- | ------------------- |
| POST   | `/api/clients`         | Create a client     |
| GET    | `/api/clients/{id}`    | Get a client        |
| PUT    | `/api/clients/{id}`    | Update a client     |
| DELETE | `/api/clients/{id}`    | Delete a client     |
| POST   | `/api/accounts`        | Open an account     |
| DELETE | `/api/accounts/{id}`   | Close an account    |

## Repo layout

```
infra/               Terraform (VPC, Aurora, RDS Proxy, Lambdas, API Gateway)
lambdas/clients/     Clients Lambda
lambdas/accounts/    Accounts Lambda
db/schema.sql        Tables and grants
docs/                Notes, e.g. building the psycopg2 Lambda layer
.github/workflows/   Deploy, destroy, and DB migration workflows
```

## Running it yourself

### 1. One-time setup

Terraform keeps its state in S3 with a DynamoDB lock table, so create those first:

```bash
aws s3api create-bucket --bucket my-terraform-state-crm --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
aws s3api put-bucket-versioning --bucket my-terraform-state-crm \
  --versioning-configuration Status=Enabled

aws dynamodb create-table --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

You'll also need:

- A Secrets Manager secret called `crm-dev-db-credentials` with a `username` and `password`.
- An IAM role that GitHub Actions can assume through OIDC, saved as the
  `AWS_ROLE_TO_ASSUME` repo secret.
- A psycopg2 Lambda layer. [`docs/Layer_init.txt`](docs/Layer_init.txt) shows how to build one.

### 2. Deploy, migrate, destroy

All three workflows are started by hand from the **Actions** tab:

- **Deploy CRM Feature 2** packages the Lambdas and runs `terraform apply`. If the
  apply fails, it cleans up after itself.
- **Database Migration** runs `db/schema.sql` against Aurora through the RDS Data API.
- **Destroy CRM Infra** runs `terraform destroy`. Aurora and RDS Proxy cost money
  while they're up, so remember to run it when you're done.

## Status

This is a work in progress. I moved the Lambdas from IAM database auth to
Secrets Manager credentials with Cognito checks, but `infra/main.tf` hasn't caught
up yet. The handler names and environment variables it sets still match the old
version, so expect to fix those before a full deploy works. Also, the token check
currently decodes the JWT without verifying its signature, so don't treat this as
production-ready.
