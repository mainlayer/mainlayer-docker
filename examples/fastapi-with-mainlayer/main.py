"""
FastAPI service with Mainlayer payment verification sidecar.

The Mainlayer sidecar runs alongside this app in Docker Compose and exposes
a local HTTP endpoint for verifying that an incoming request has been paid for.

Before serving any paid endpoint, call verify_payment() which forwards the
request's Authorization header to the sidecar and checks the result.
"""

import os
import httpx
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.responses import JSONResponse

app = FastAPI(
    title="My Paid API",
    description="Example FastAPI service protected by Mainlayer payment verification",
    version="1.0.0",
)

# Address of the Mainlayer sidecar (set via environment variable in Docker Compose)
MAINLAYER_SIDECAR_URL = os.environ.get("MAINLAYER_SIDECAR_URL", "http://mainlayer-verify:3000")
SIDECAR_TIMEOUT = float(os.environ.get("MAINLAYER_TIMEOUT", "10"))


# ── Dependency: verify payment ────────────────────────────────────────────────

async def verify_payment(request: Request) -> dict:
    """
    Forwards the incoming request's Authorization header to the Mainlayer
    sidecar to verify that the request has been paid for.

    Returns the verified payment metadata on success.
    Raises HTTP 402 Payment Required if verification fails.
    """
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(
            status_code=402,
            detail="Payment required. Include your Mainlayer payment token in the Authorization header.",
        )

    async with httpx.AsyncClient(timeout=SIDECAR_TIMEOUT) as client:
        try:
            response = await client.post(
                f"{MAINLAYER_SIDECAR_URL}/verify",
                headers={"Authorization": auth_header},
                json={
                    "path": str(request.url.path),
                    "method": request.method,
                },
            )
        except httpx.ConnectError:
            raise HTTPException(
                status_code=503,
                detail="Payment verification service unavailable.",
            )

    if response.status_code == 200:
        return response.json()
    elif response.status_code == 402:
        raise HTTPException(
            status_code=402,
            detail="Payment required or insufficient balance.",
        )
    elif response.status_code == 401:
        raise HTTPException(
            status_code=401,
            detail="Invalid payment token.",
        )
    else:
        raise HTTPException(
            status_code=502,
            detail=f"Unexpected response from payment service: {response.status_code}",
        )


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    """Public health check — no payment required."""
    return {"status": "ok"}


@app.get("/api/v1/data", dependencies=[Depends(verify_payment)])
async def get_data():
    """
    Paid endpoint. Returns data only after the payment token is verified
    by the Mainlayer sidecar.
    """
    return {
        "message": "Here is your paid data.",
        "records": [
            {"id": 1, "value": "alpha"},
            {"id": 2, "value": "beta"},
            {"id": 3, "value": "gamma"},
        ],
    }


@app.post("/api/v1/inference")
async def run_inference(request: Request, payment: dict = Depends(verify_payment)):
    """
    Paid inference endpoint. The payment metadata is available via the
    `payment` dependency for logging or downstream use.
    """
    body = await request.json()
    prompt = body.get("prompt", "")

    # Log the payment request ID for reconciliation
    payment_request_id = payment.get("request_id", "unknown")
    print(f"[inference] Serving request {payment_request_id}")

    return {
        "result": f"Inference result for: {prompt}",
        "payment_request_id": payment_request_id,
        "tokens_used": len(prompt.split()),
    }


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
    )
