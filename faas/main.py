import json
from datetime import datetime, timezone

import functions_framework


_CORS_HEADERS = {
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
}


@functions_framework.http
def faas(request):
    """Small HTTP FaaS endpoint used to verify the Google Cloud deployment."""
    if request.method == "OPTIONS":
        return ("", 204, _CORS_HEADERS)

    trace_header = request.headers.get("X-Cloud-Trace-Context", "")
    request_id = trace_header.split("/", maxsplit=1)[0] or None

    response = {
        "service": "devcloud-faas",
        "cloud": "gcp",
        "status": "ready",
        "request_id": request_id,
        "method": request.method,
        "path": request.path,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    return (json.dumps(response), 200, _CORS_HEADERS)
