import os
import json
import boto3
import psycopg2
import uuid
import logging
import jwt  # PyJWT required in deployment package


logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ==========================
# Environment & Secrets
# ==========================
DB_HOST = os.environ["DB_HOST"]  # RDS Proxy endpoint
DB_NAME = os.environ.get("DB_NAME")
DB_PORT = int(os.environ.get("DB_PORT"))
SECRET_ARN = os.environ["SECRET_ARN"]


# AWS clients
sm = boto3.client("secretsmanager")
cognito = boto3.client('cognito-idp')


# Retrieve DB credentials from Secrets Manager once at cold start
try:
    secret_value = sm.get_secret_value(SecretId=SECRET_ARN)
    SECRET = json.loads(secret_value["SecretString"])
    logger.info(f"Retrieved secret {SECRET_ARN}")
except Exception as e:
    logger.error(f"Failed to retrieve secret {SECRET_ARN}: {e}")
    SECRET = None  # fail gracefully


def get_db_connection():
    """Connect to Aurora via RDS Proxy using psycopg2 and Secrets Manager creds."""
    if not SECRET:
        raise Exception("DB credentials are not available")
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=SECRET["username"],
        password=SECRET["password"],
        connect_timeout=5,
    )


# ==========================
# CRUD Operations
# ==========================
def create_client(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        client_id = str(uuid.uuid4())
        sql = """
            INSERT INTO clients (client_id, first_name, last_name, email, phone)
            VALUES (%s, %s, %s, %s, %s)
        """

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, (
                    client_id,
                    body.get("firstName"),
                    body.get("lastName"),
                    body.get("email"),
                    body.get("phone"),
                ))
            conn.commit()

        logger.info(f"Created client {client_id}")
        return {"statusCode": 201, "body": json.dumps({"id": client_id, **body})}

    except Exception as e:
        logger.error(f"Create failed: {e}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def delete_client(event, context):
    try:
        client_id = event.get("pathParameters", {}).get("id")
        if not client_id:
            logger.warning("Delete failed: Missing client ID")
            return {"statusCode": 400, "body": json.dumps({"error": "Missing client ID"})}

        sql = "DELETE FROM clients WHERE client_id = %s"

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, (client_id,))
            conn.commit()

        logger.info(f"Deleted client {client_id}")
        return {"statusCode": 200, "body": json.dumps({"id": client_id, "status": "deleted"})}

    except Exception as e:
        logger.error(f"Delete failed: {e}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def get_client(event, context):
    try:
        client_id = event.get("pathParameters", {}).get("id")
        logger.info(f"Fetching client with ID: {client_id}")
        if not client_id:
            logger.warning("Get failed: Missing client ID")
            return {"statusCode": 400, "body": json.dumps({"error": "Missing client ID"})}

        sql = """
            SELECT client_id, first_name, last_name, email, phone
            FROM clients
            WHERE client_id = %s
        """

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, (client_id,))
                row = cur.fetchone()

        if not row:
            logger.info(f"Client not found: {client_id}")
            return {"statusCode": 404, "body": json.dumps({"error": "Client not found"})}

        client = {
            "id": row[0],
            "firstName": row[1],
            "lastName": row[2],
            "email": row[3],
            "phone": row[4],
        }

        logger.info(f"Client found: {client_id}")
        return {"statusCode": 200, "body": json.dumps(client)}

    except Exception as e:
        logger.error(f"Get failed: {e}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def update_client(event, context):
    try:
        client_id = event.get("pathParameters", {}).get("id")
        if not client_id:
            logger.warning("Update failed: Missing client ID")
            return {"statusCode": 400, "body": json.dumps({"error": "Missing client ID"})}

        body = json.loads(event.get("body", "{}"))
        sql = """
            UPDATE clients
            SET first_name = %s,
                last_name = %s,
                email = %s,
                phone = %s
            WHERE client_id = %s
        """

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, (
                    body.get("firstName"),
                    body.get("lastName"),
                    body.get("email"),
                    body.get("phone"),
                    client_id,
                ))
            conn.commit()

        logger.info(f"Updated client {client_id}")
        return {"statusCode": 200, "body": json.dumps({"id": client_id, **body})}

    except Exception as e:
        logger.error(f"Update failed: {e}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def verify_client(event, context):
    try:
        client_id = event.get("pathParameters", {}).get("id")
        if not client_id:
            logger.warning("Verify failed: Missing client ID")
            return {"statusCode": 400, "body": json.dumps({"error": "Missing client ID"})}

        sql = """
            UPDATE clients
            SET status = %s
            WHERE client_id = %s
        """

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, ("VERIFIED", client_id))
            conn.commit()

        logger.info(f"Verified client {client_id}")
        return {"statusCode": 200, "body": json.dumps({"id": client_id, "status": "VERIFIED"})}

    except Exception as e:
        logger.error(f"Verify failed: {e}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


# ==========================
# Router (main handler) with cognito JWT group authorization
# ==========================
def lambda_handler(event, context):
    
    cors_headers = {
        'Access-Control-Allow-Origin': os.environ.get('ALLOWED_ORIGIN', '*'),
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }

    if event.get("requestContext", {}).get("http", {}).get("method") == 'OPTIONS':
        return {'statusCode': 200, 'headers': cors_headers, 'body': ''}
    
    # Extract Authorization header and decode token
    headers = event.get('headers', {})
    auth_header = headers.get('Authorization') or headers.get('authorization') or ''
    logger.info("Event: %s", json.dumps(event))
    if not auth_header.startswith('Bearer '):
        return {
            'statusCode': 401,
            'headers': cors_headers,
            'body': json.dumps({
                "error": "Unauthorized: Missing or invalid Authorization header",
                "event": event
            })
        }
    token = auth_header.split(' ')[1]

    # JWT decode
    try:
        decoded = jwt.decode(token, options={"verify_signature": False})
        groups = decoded.get("cognito:groups", [])
        username = decoded.get("username")
        logger.info(f"JWT decoded. Username: {username}, Groups: {groups}")
    except Exception as e:
        logger.warning(f"Unauthorized: Invalid token: {e}")
        return {
            "statusCode": 401,
            "headers": cors_headers,
            "body": json.dumps({"error": "Unauthorized: Invalid token"}),
        }

    user_pool_id = os.environ.get("COGNITO_USER_POOL_ID")
    if not user_pool_id:
        logger.error("Server misconfigured: no COGNITO_USER_POOL_ID set")
        return {
            "statusCode": 500,
            "headers": cors_headers,
            "body": json.dumps({"error": "Server misconfigured: no COGNITO_USER_POOL_ID set"}),
        }

    # JWT group check
    if "ITSAagent" not in groups:
        logger.warning("Forbidden: User does not belong to ITSAagent (JWT check)")
        return {
            "statusCode": 403,
            "headers": cors_headers,
            "body": json.dumps({"error": "Forbidden: User does not belong to ITSAagent (JWT check)"}),
        }

    # Verify group membership with Cognito
    try:
        if username:
            resp = cognito.admin_list_groups_for_user(
                UserPoolId=user_pool_id,
                Username=username
            )
            server_groups = [g['GroupName'] for g in resp.get('Groups', [])]
            if "ITSAagent" not in server_groups:
                logger.warning("Forbidden: User is not in ITSAagent (checked with Cognito API)")
                return {
                    "statusCode": 403,
                    "headers": cors_headers,
                    "body": json.dumps({"error": "Forbidden: User is not in ITSAagent (checked with Cognito API)"}),
                }
    except Exception as e:
        logger.error(f"Cognito group query exception for user {username}: {e}", exc_info=True)

    
    # Routing (API Gateway HTTP API, payload format 2.0)
    method = event.get("requestContext", {}).get("http", {}).get("method")
    route = event.get("requestContext", {}).get("http", {}).get("path", "")
    logger.info(f"Routing request: {method} {route}")

    if method == "POST" and route == "/api/clients":
        return create_client(event, context)
    elif method == "POST" and route.startswith("/api/clients/") and route.endswith("/verify"):
        return verify_client(event, context)
    elif method == "GET" and route.startswith("/api/clients/"):
        return get_client(event, context)
    elif method == "PUT" and route.startswith("/api/clients/"):
        return update_client(event, context)
    elif method == "DELETE" and route.startswith("/api/clients/"):
        return delete_client(event, context)
    else:
        logger.warning(f"Not found: {method} {route}")
        return {"statusCode": 404, "body": json.dumps({"error": "Not found", "route": route})}
