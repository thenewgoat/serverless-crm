import json
import uuid
import boto3
import os

rds = boto3.client("rds-data")

DB_ARN = os.environ["AURORA_CLUSTER_ARN"]
SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
DB_NAME = os.environ["DB_NAME"]


def execute_sql(sql, params=[]):
    """Helper to execute SQL against Aurora via Data API."""
    return rds.execute_statement(
        resourceArn=DB_ARN,
        secretArn=SECRET_ARN,
        database=DB_NAME,
        sql=sql,
        parameters=params
    )


def create_client(event, context):
    body = json.loads(event.get("body", "{}"))
    client_id = f"client_{uuid.uuid4().hex[:8]}"

    sql = """
        INSERT INTO clients (client_id, first_name, last_name, email_address, phone_number)
        VALUES (:client_id, :first_name, :last_name, :email_address, :phone_number)
    """
    params = [
        {"name": "client_id", "value": {"stringValue": client_id}},
        {"name": "first_name", "value": {"stringValue": body.get("firstName", "")}},
        {"name": "last_name", "value": {"stringValue": body.get("lastName", "")}},
        {"name": "email_address", "value": {"stringValue": body.get("email", "")}},
        {"name": "phone_number", "value": {"stringValue": body.get("phone", "")}},
    ]

    execute_sql(sql, params)

    return {
        "statusCode": 201,
        "body": json.dumps({"id": client_id, **body})
    }


def get_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")

    sql = "SELECT client_id, first_name, last_name, email_address, phone_number FROM clients WHERE client_id = :client_id"
    params = [{"name": "client_id", "value": {"stringValue": client_id}}]

    result = execute_sql(sql, params)
    if not result.get("records"):
        return {"statusCode": 404, "body": json.dumps({"error": "Client not found"})}

    record = result["records"][0]
    client = {
        "id": record[0]["stringValue"],
        "firstName": record[1]["stringValue"],
        "lastName": record[2]["stringValue"],
        "email": record[3]["stringValue"],
        "phone": record[4]["stringValue"],
    }

    return {"statusCode": 200, "body": json.dumps(client)}


def update_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")
    body = json.loads(event.get("body", "{}"))

    sql = """
        UPDATE clients
        SET first_name = :first_name,
            last_name = :last_name,
            email_address = :email_address,
            phone_number = :phone_number
        WHERE client_id = :client_id
    """
    params = [
        {"name": "first_name", "value": {"stringValue": body.get("firstName", "")}},
        {"name": "last_name", "value": {"stringValue": body.get("lastName", "")}},
        {"name": "email_address", "value": {"stringValue": body.get("email", "")}},
        {"name": "phone_number", "value": {"stringValue": body.get("phone", "")}},
        {"name": "client_id", "value": {"stringValue": client_id}},
    ]

    execute_sql(sql, params)

    return {
        "statusCode": 200,
        "body": json.dumps({"id": client_id, **body})
    }


def delete_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")

    sql = "DELETE FROM clients WHERE client_id = :client_id"
    params = [{"name": "client_id", "value": {"stringValue": client_id}}]

    execute_sql(sql, params)

    return {
        "statusCode": 200,
        "body": json.dumps({"id": client_id, "status": "deleted"})
    }


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
