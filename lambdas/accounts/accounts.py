import json
import os
import uuid
import boto3
import pg8000
from botocore.exceptions import ClientError

# Environment variables from Terraform
REGION = os.environ["REGION"]
DB_HOST = os.environ["DB_HOST"]
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ["DB_NAME"]
DB_SECRET_NAME = os.environ["DB_SECRET_NAME"]  # now used for user lookup

rds = boto3.client("rds")
secretsmanager = boto3.client("secretsmanager")


def get_db_user():
    """Fetch DB user from Secrets Manager instead of hardcoding in env."""
    try:
        resp = secretsmanager.get_secret_value(SecretId=DB_SECRET_NAME)
        secret = json.loads(resp["SecretString"])
        return secret["username"]
    except ClientError as e:
        raise RuntimeError(f"Failed to retrieve DB user from Secrets Manager: {e}")


def get_db_connection():
    """Generate IAM auth token and connect to Aurora via RDS Proxy using pg8000."""
    db_user = get_db_user()
    token = rds.generate_db_auth_token(
        DBHostname=DB_HOST,
        Port=DB_PORT,
        DBUsername=db_user,
        Region=REGION,
    )

    return pg8000.connect(
        user=db_user,
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        password=token,
        ssl_context=True,
    )


# ==========================
# CRUD Operations
# ==========================

def create_account(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        account_id = str(uuid.uuid4())

        sql = """
            INSERT INTO accounts (
                account_id, client_id, account_type, status,
                opening_date, initial_deposit, currency, branch_id
            )
            VALUES (:1, :2, :3, :4, CURRENT_DATE, :5, :6, :7)
        """

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    sql,
                    (
                        account_id,
                        body.get("clientId"),
                        body.get("accountType", "Savings"),
                        "Active",
                        float(body.get("initialDeposit", 0)),
                        body.get("currency", "SGD"),
                        body.get("branchId", "MAIN"),
                    ),
                )
            conn.commit()

        return {"statusCode": 201, "body": json.dumps({"id": account_id, **body})}

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def delete_account(event, context):
    try:
        account_id = event.get("pathParameters", {}).get("id")
        if not account_id:
            return {"statusCode": 400, "body": json.dumps({"error": "Missing account ID"})}

        sql = "DELETE FROM accounts WHERE account_id = :1"

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, (account_id,))
            conn.commit()

        return {"statusCode": 200, "body": json.dumps({"id": account_id, "status": "deleted"})}

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


# ==========================
# Main handler
# ==========================

def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method")
    route = event.get("requestContext", {}).get("http", {}).get("path")

    if method == "POST" and route == "/api/accounts":
        return create_account(event, context)
    elif method == "DELETE" and route.startswith("/api/accounts/"):
        return delete_account(event, context)
    else:
        return {"statusCode": 404, "body": json.dumps({"error": "Not found"})}
