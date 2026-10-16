import asyncio

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Bridge fixture", instructions="Instructions survive the bridge.")


@mcp.tool()
async def echo(text: str) -> str:
    return text


@mcp.tool()
async def slow() -> str:
    await asyncio.sleep(60)
    return "finished"


@mcp.resource("fixture://hello")
def hello() -> str:
    return "Resource content"


if __name__ == "__main__":
    mcp.run(transport="stdio")
