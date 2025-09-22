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

def create_client(event, context):
    body = json.loads(event.get("body", "{}"))
    client_id = str(uuid.uuid4())

    sql = """
        INSERT INTO clients (client_id, first_name, last_name, email, phone)
        VALUES (%s, %s, %s, %s, %s)
    """

    with get_db_connection() as conn:
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


def get_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")

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
        return {"statusCode": 404, "body": json.dumps({"error": "Client not found"})}

    client = {
        "id": row[0],
        "firstName": row[1],
        "lastName": row[2],
        "email": row[3],
        "phone": row[4],
    }

    return {"statusCode": 200, "body": json.dumps(client)}


def update_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")
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


def delete_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")

    sql = "DELETE FROM clients WHERE client_id = %s"

    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (client_id,))
        conn.commit()

    return {"statusCode": 200, "body": json.dumps({"id": client_id, "status": "deleted"})}


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
