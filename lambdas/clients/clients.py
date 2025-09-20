import json, uuid

def create_client(event, context):
    body = json.loads(event.get("body", "{}"))
    client_id = f"client_{uuid.uuid4().hex[:8]}"
    return {
        "statusCode": 201,
        "body": json.dumps({ "id": client_id, **body })
    }

def get_client(event, context):
    client_id = event.get("pathParameters", {}).get("id", "unknown")
    return {
        "statusCode": 200,
        "body": json.dumps({ "id": client_id, "firstName": "Alice", "lastName": "Tan" })
    }

def update_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")
    body = json.loads(event.get("body", "{}"))
    return {
        "statusCode": 200,
        "body": json.dumps({ "id": client_id, **body })
    }

def delete_client(event, context):
    client_id = event.get("pathParameters", {}).get("id")
    return {
        "statusCode": 200,
        "body": json.dumps({ "id": client_id, "status": "deleted" })
    }
