import json
import os
import uuid
import boto3
import psycopg2

# Environment variables from Terraform
REGION = os.environ["REGION"]
DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]

rds = boto3.client("rds")


def get_db_connection():
    """Generate IAM auth token and connect to Aurora via RDS Proxy."""
    token = rds.generate_db_auth_token(
        DBHostname=DB_HOST,
        Port=int(DB_PORT),
        DBUsername=DB_USER,
        Region=REGION,
    )

    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=token,
        database=DB_NAME,
        sslmode="require",
    )
    return conn


# ==========================
# CRUD Operations
# ==========================

def create_account(event, context):
    body = json.loads(event.get("body", "{}"))
    account_id = str(uuid.uuid4())

    sql = """
        INSERT INTO accounts (
            account_id, client_id, account_type, status,
            opening_date, initial_deposit, currency, branch_id
        )
        VALUES (%s, %s, %s, %s, CURRENT_DATE, %s, %s, %s)
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


def delete_account(event, context):
    account_id = event.get("pathParameters", {}).get("id")

    sql = "DELETE FROM accounts WHERE account_id = %s"

    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (account_id,))
        conn.commit()

    return {"statusCode": 200, "body": json.dumps({"id": account_id, "status": "deleted"})}


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
