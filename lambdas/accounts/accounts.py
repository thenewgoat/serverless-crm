import json
import uuid
import boto3
import os

rds = boto3.client("rds-data")

DB_ARN = os.environ["AURORA_CLUSTER_ARN"]
SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
DB_NAME = os.environ["DB_NAME"]


def execute_sql(sql, params=[]):
    return rds.execute_statement(
        resourceArn=DB_ARN,
        secretArn=SECRET_ARN,
        database=DB_NAME,
        sql=sql,
        parameters=params
    )


def create_account(event, context):
    body = json.loads(event.get("body", "{}"))
    account_id = f"acct_{uuid.uuid4().hex[:8]}"

    sql = """
        INSERT INTO accounts (account_id, client_id, account_type, account_status, opening_date, initial_deposit, currency)
        VALUES (:account_id, :client_id, :account_type, :account_status, current_date, :initial_deposit, :currency)
    """
    params = [
        {"name": "account_id", "value": {"stringValue": account_id}},
        {"name": "client_id", "value": {"stringValue": body.get("clientId", "")}},
        {"name": "account_type", "value": {"stringValue": body.get("accountType", "Savings")}},
        {"name": "account_status", "value": {"stringValue": "Active"}},
        {"name": "initial_deposit", "value": {"doubleValue": float(body.get("initialDeposit", 0))}},
        {"name": "currency", "value": {"stringValue": body.get("currency", "SGD")}},
    ]

    execute_sql(sql, params)

    return {
        "statusCode": 201,
        "body": json.dumps({"id": account_id, **body})
    }


def delete_account(event, context):
    account_id = event.get("pathParameters", {}).get("id")

    sql = "DELETE FROM accounts WHERE account_id = :account_id"
    params = [{"name": "account_id", "value": {"stringValue": account_id}}]

    execute_sql(sql, params)

    return {
        "statusCode": 200,
        "body": json.dumps({"id": account_id, "status": "deleted"})
    }


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method")
    route = event.get("requestContext", {}).get("http", {}).get("path")

    if method == "POST" and route == "/api/accounts":
        return create_account(event, context)
    elif method == "DELETE" and route.startswith("/api/accounts/"):
        return delete_account(event, context)
    else:
        return {"statusCode": 404, "body": json.dumps({"error": "Not found"})}
