# clients.py
import json
import os
import uuid
import boto3
import pg8000
import ssl

import logging

REGION  = os.environ["REGION"]
DB_HOST = os.environ["DB_HOST"]   # <-- proxy endpoint (not cluster)
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]

rds = boto3.client("rds")
_conn = None

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def _connect_new():
    token = rds.generate_db_auth_token(
        DBHostname=DB_HOST,
        Port=DB_PORT,
        DBUsername=DB_USER,
        Region=REGION,
    )
    
    logger.info(token)

    # If using a minimal container, consider supplying cafile to verify RDS certs.
    # ctx = ssl.create_default_context(cafile="/opt/rds-combined-ca-bundle.pem")
    ctx = ssl.create_default_context()
    conn = pg8000.connect(
        user=DB_USER,
        host=DB_HOST,        # RDS Proxy endpoint
        port=DB_PORT,
        database=DB_NAME,
        password=token,      # IAM token is used only at login time
        ssl_context=ctx,     # TLS required for IAM -> Proxy
        tcp_keepalive=True,  # keepalive helps long-lived Lambda runtimes
        application_name="crm-clients-lambda",
    )
    # Optional: tighten session behavior to reduce proxy pinning
    with conn.cursor() as cur:
        cur.execute("SET idle_in_transaction_session_timeout = '15s';")
        cur.execute("SET statement_timeout = '30s';")
    return conn

def get_db_connection():
    global _conn
    try:
        if _conn is None:
            _conn = _connect_new()
        else:
            # Validate connection by pinging the backend
            try:
                with _conn.cursor() as cur:
                    cur.execute("SELECT 1;")
            except Exception:
                _conn = _connect_new()
        return _conn
    except Exception as e:
        print(f"DB connection error: {e}")
        raise


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

        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (
                    client_id,
                    body.get("firstName"),
                    body.get("lastName"),
                    body.get("email"),
                    body.get("phone"),
                ),
            )
        conn.commit()

        return {"statusCode": 201, "body": json.dumps({"id": client_id, **body})}

    except Exception as e:
        print(f"create_client error: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def get_client(event, context):
    try:
        client_id = event.get("pathParameters", {}).get("id")
        if not client_id:
            return {"statusCode": 400, "body": json.dumps({"error": "Missing client ID"})}

        sql = """
            SELECT client_id, first_name, last_name, email, phone
            FROM clients
            WHERE client_id = %s
        """

        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute(sql, (client_id,))
            row = cur.fetchone()

        if not row:
            return {"statusCode": 404, "body": json.dumps({"error": "Client not found"})}

        client = {
            "id": row[0],
            "firstName": row[1],
            "lastName": row[2],
            "email": row[3],
            "phone": row[4],
        }

        return {"statusCode": 200, "body": json.dumps(client)}

    except Exception as e:
        print(f"get_client error: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def update_client(event, context):
    try:
        client_id = event.get("pathParameters", {}).get("id")
        if not client_id:
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

        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute(
                sql,
                (
                    body.get("firstName"),
                    body.get("lastName"),
                    body.get("email"),
                    body.get("phone"),
                    client_id,
                ),
            )
        conn.commit()

        return {"statusCode": 200, "body": json.dumps({"id": client_id, **body})}

    except Exception as e:
        print(f"update_client error: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def delete_client(event, context):
    try:
        client_id = event.get("pathParameters", {}).get("id")
        if not client_id:
            return {"statusCode": 400, "body": json.dumps({"error": "Missing client ID"})}

        sql = "DELETE FROM clients WHERE client_id = %s"

        conn = get_db_connection()
        with conn.cursor() as cur:
            cur.execute(sql, (client_id,))
        conn.commit()

        return {"statusCode": 200, "body": json.dumps({"id": client_id, "status": "deleted"})}

    except Exception as e:
        print(f"delete_client error: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


# ==========================
# Main handler
# ==========================

def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method")
    route = event.get("requestContext", {}).get("http", {}).get("path")

    if method == "POST" and route == "/api/clients":
        return create_client(event, context)
    elif method == "GET" and route.startswith("/api/clients/"):
        return get_client(event, context)
    elif method == "PUT" and route.startswith("/api/clients/"):
        return update_client(event, context)
    elif method == "DELETE" and route.startswith("/api/clients/"):
        return delete_client(event, context)
    else:
        return {"statusCode": 404, "body": json.dumps({"error": "Not found"})}
