import asyncio

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Bridge fixture", instructions="Instructions survive the bridge.")


@mcp.tool()
async def echo(text: str) -> str:
    return text


@mcp.tool()
def large() -> dict[str, str]:
    # Fits Radicale's 2 MiB application budget, but the MCP representation
    # contains both text and structured copies and is substantially larger.
    return {"value": "x" * (2 * 1024 * 1024 - 1024)}


@mcp.tool()
async def slow() -> str:
    await asyncio.sleep(60)
    return "finished"


@mcp.resource("fixture://hello")
def hello() -> str:
    return "Resource content"


if __name__ == "__main__":
    mcp.run(transport="stdio")
