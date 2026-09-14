import os
import json
import uuid
import boto3
import psycopg2
import logging
import jwt  # PyJWT needed in your deployment package

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ==========================
# Environment & Secrets
# ==========================
DB_HOST = os.environ["DB_HOST"]   # RDS Proxy endpoint
DB_NAME = os.environ.get("DB_NAME", "client_account_db_test")
DB_PORT = int(os.environ.get("DB_PORT", 5432))
SECRET_ARN = os.environ["SECRET_ARN"]

sm = boto3.client("secretsmanager")
secret_value = sm.get_secret_value(SecretId=SECRET_ARN)
SECRET = json.loads(secret_value["SecretString"])
logger.info(f"Retrieved secret {SECRET_ARN}")


def get_db_connection():
    """Connect to Aurora via RDS Proxy using psycopg2 + Secrets Manager creds."""
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=SECRET["username"],
        password=SECRET["password"],
        connect_timeout=5,
    )


# ==========================
# CRUD Operations (Accounts)
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

    except Exception as e:
        logger.error(f"Create account failed: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def delete_account(event, context):
    try:
        account_id = event.get("pathParameters", {}).get("id")
        if not account_id:
            return {"statusCode": 400, "body": json.dumps({"error": "Missing account ID"})}

        sql = "DELETE FROM accounts WHERE account_id = %s"

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, (account_id,))
            conn.commit()

        return {"statusCode": 200, "body": json.dumps({"id": account_id, "status": "deleted"})}

    except Exception as e:
        logger.error(f"Delete account failed: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


# ==========================
# Router (main handler) — with Cognito JWT group authorization
# ==========================
cognito = boto3.client("cognito-idp")

def lambda_handler(event, context):
    cors_headers = {
        'Access-Control-Allow-Origin': os.environ.get('ALLOWED_ORIGIN', '*'),
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }

    # Handle CORS preflight
    if event.get("requestContext", {}).get("http", {}).get("method") == 'OPTIONS':
        return {"statusCode": 200, "headers": cors_headers, "body": ""}

    # --- AUTHENTICATION & GROUP CHECK START ---
    # HTTP API lowercases header names
    headers = event.get('headers', {})
    auth_header = headers.get('Authorization') or headers.get('authorization') or ''
    if not auth_header.startswith('Bearer '):
        return {
            "statusCode": 401,
            "headers": cors_headers,
            "body": json.dumps({"error": "Unauthorized: Missing or invalid Authorization header"}),
        }
    token = auth_header.split(' ')[1]

    try:
        decoded = jwt.decode(token, options={"verify_signature": False})
        groups = decoded.get("cognito:groups", [])
        username = decoded.get("username")
    except Exception:
        return {
            "statusCode": 401,
            "headers": cors_headers,
            "body": json.dumps({"error": "Unauthorized: Invalid token"}),
        }

    user_pool_id = os.environ.get("COGNITO_USER_POOL_ID")
    if not user_pool_id:
        return {
            "statusCode": 500,
            "headers": cors_headers,
            "body": json.dumps({"error": "Server misconfigured: no COGNITO_USER_POOL_ID set"}),
        }

    # JWT group check
    if "ITSAagent" not in groups:
        return {
            "statusCode": 403,
            "headers": cors_headers,
            "body": json.dumps({"error": "Forbidden: User does not belong to ITSAagent (JWT check)"}),
        }

    try:
        if username:
            resp = cognito.admin_list_groups_for_user(
                UserPoolId=user_pool_id,
                Username=username
            )
            server_groups = [g['GroupName'] for g in resp.get('Groups', [])]
            if "ITSAagent" not in server_groups:
                return {
                    "statusCode": 403,
                    "headers": cors_headers,
                    "body": json.dumps({"error": "Forbidden: User is not in ITSAagent (checked with Cognito API)"}),
                }
    except Exception as e:
        logger.error(f"Cognito group query exception for user {username}: {e}")

    # ==========================
    # Route handling
    # ==========================
    method = event.get("requestContext", {}).get("http", {}).get("method")
    route = event.get("requestContext", {}).get("http", {}).get("path")

    if method == "POST" and route == "/api/accounts":
        return create_account(event, context)
    elif method == "DELETE" and route.startswith("/api/accounts/"):
        return delete_account(event, context)
    else:
        return {"statusCode": 404, "body": json.dumps({"error": "Not found"})}
