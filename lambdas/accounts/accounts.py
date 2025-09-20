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
