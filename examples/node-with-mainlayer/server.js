"use strict";

/**
 * Node.js HTTP service with Mainlayer payment verification sidecar.
 *
 * The Mainlayer sidecar verifies that each request carries a valid payment
 * token before this service serves any paid response.
 *
 * Usage:
 *   MAINLAYER_SIDECAR_URL=http://mainlayer-verify:3000 node server.js
 */

const http = require("http");
const https = require("https");
const { URL } = require("url");

const PORT = parseInt(process.env.PORT || "8080", 10);
const SIDECAR_URL = process.env.MAINLAYER_SIDECAR_URL || "http://mainlayer-verify:3000";
const SIDECAR_TIMEOUT_MS = parseInt(process.env.MAINLAYER_TIMEOUT || "10", 10) * 1000;

// ── Utility: forward JSON request to sidecar ──────────────────────────────────

/**
 * Sends a verification request to the Mainlayer sidecar.
 * @param {string} authHeader - The Authorization header from the incoming request.
 * @param {string} path       - The request path being accessed.
 * @param {string} method     - The HTTP method.
 * @returns {Promise<{ok: boolean, status: number, body: object}>}
 */
function verifySidecar(authHeader, path, method) {
  return new Promise((resolve, reject) => {
    const url = new URL("/verify", SIDECAR_URL);
    const body = JSON.stringify({ path, method });

    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      path: url.pathname,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
        Authorization: authHeader,
      },
      timeout: SIDECAR_TIMEOUT_MS,
    };

    const transport = url.protocol === "https:" ? https : http;

    const req = transport.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => {
        try {
          resolve({ ok: res.statusCode === 200, status: res.statusCode, body: JSON.parse(data) });
        } catch {
          resolve({ ok: false, status: res.statusCode, body: {} });
        }
      });
    });

    req.on("timeout", () => {
      req.destroy();
      reject(new Error("Sidecar request timed out"));
    });

    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

// ── Middleware: require payment ───────────────────────────────────────────────

async function requirePayment(req, res) {
  const authHeader = req.headers["authorization"];
  if (!authHeader) {
    res.writeHead(402, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Payment required. Include your Mainlayer payment token in the Authorization header." }));
    return null;
  }

  let verification;
  try {
    verification = await verifySidecar(authHeader, req.url, req.method);
  } catch (err) {
    console.error("[mainlayer] Sidecar error:", err.message);
    res.writeHead(503, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Payment verification service unavailable." }));
    return null;
  }

  if (!verification.ok) {
    const status = verification.status === 401 ? 401 : 402;
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Payment required or token invalid.", detail: verification.body }));
    return null;
  }

  return verification.body;
}

// ── Route handlers ────────────────────────────────────────────────────────────

function sendJson(res, status, data) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data));
}

async function handleRequest(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);

  // Public: health check
  if (url.pathname === "/health" && req.method === "GET") {
    return sendJson(res, 200, { status: "ok" });
  }

  // Paid: data endpoint
  if (url.pathname === "/api/v1/data" && req.method === "GET") {
    const payment = await requirePayment(req, res);
    if (!payment) return;

    return sendJson(res, 200, {
      message: "Here is your paid data.",
      payment_request_id: payment.request_id,
      records: [
        { id: 1, value: "alpha" },
        { id: 2, value: "beta" },
        { id: 3, value: "gamma" },
      ],
    });
  }

  // Paid: inference endpoint
  if (url.pathname === "/api/v1/inference" && req.method === "POST") {
    const payment = await requirePayment(req, res);
    if (!payment) return;

    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
      let parsed = {};
      try { parsed = JSON.parse(body); } catch { /* ignore */ }

      const prompt = parsed.prompt || "";
      console.log(`[inference] Serving request ${payment.request_id}`);

      sendJson(res, 200, {
        result: `Inference result for: ${prompt}`,
        payment_request_id: payment.request_id,
        tokens_used: prompt.split(/\s+/).length,
      });
    });
    return;
  }

  // 404 fallback
  sendJson(res, 404, { error: "Not found" });
}

// ── Server ────────────────────────────────────────────────────────────────────

const server = http.createServer((req, res) => {
  handleRequest(req, res).catch((err) => {
    console.error("[server] Unhandled error:", err);
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Internal server error" }));
  });
});

server.listen(PORT, () => {
  console.log(`[server] Listening on port ${PORT}`);
  console.log(`[server] Mainlayer sidecar: ${SIDECAR_URL}`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("[server] SIGTERM received — shutting down");
  server.close(() => process.exit(0));
});
