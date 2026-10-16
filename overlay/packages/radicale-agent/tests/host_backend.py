"""Ordinary stdio MCP fixture; no D-Bus dependencies in the backend."""

import os
from dataclasses import replace

from radicale_agent import server
from radicale_agent.config import Config
from radicale_agent.service import CalendarService
from support import WritableBackend, config

if os.environ.get("RADICALE_TRANSPORT_LIVE") == "1":
    service = CalendarService(Config.from_env())
    assert service.config.writes_enabled
else:
    service = CalendarService(replace(config(), writes_enabled=True), WritableBackend())
server.get_service = lambda: service
server.main()
