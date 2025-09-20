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


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method")
    route  = event.get("requestContext", {}).get("http", {}).get("path")

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