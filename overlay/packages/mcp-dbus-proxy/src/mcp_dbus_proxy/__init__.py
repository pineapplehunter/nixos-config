"""Versioned, application-independent MCP transport over the session bus."""

INTERFACE = "io.github.pineapplehunter.Mcp1"
OBJECT_PATH = "/io/github/pineapplehunter/Mcp1"
# MCP can include the same application result as text and structured content.
MAX_MESSAGE_BYTES = 8 * 1024 * 1024
POLL_SECONDS = 20
