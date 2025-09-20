import json, uuid

def create_account(event, context):
    body = json.loads(event.get("body", "{}"))
    account_id = f"acct_{uuid.uuid4().hex[:8]}"
    return {
        "statusCode": 201,
        "body": json.dumps({ "id": account_id, **body })
    }

def delete_account(event, context):
    account_id = event.get("pathParameters", {}).get("id")
    return {
        "statusCode": 200,
        "body": json.dumps({ "id": account_id, "status": "deleted" })
    }

def handler(event, context):
    """Main Lambda entrypoint for all /api/accounts routes."""
    method = event.get("requestContext", {}).get("http", {}).get("method")
    route  = event.get("requestContext", {}).get("http", {}).get("path")

    if method == "POST" and route == "/api/accounts":
        return create_account(event, context)

    if method == "DELETE" and route.startswith("/api/accounts/"):
        return delete_account(event, context)

    return {
        "statusCode": 404,
        "body": json.dumps({"error": "Not found"})
    }