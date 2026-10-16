"""Host session-bus broker. Credentials never cross D-Bus."""

import asyncio
import json
import logging

from dbus_next import NameFlag, RequestNameReply
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

from .config import Config
from .errors import PublicError, failure
from .service import CalendarService
from .transport import BUS_NAME, INTERFACE, OBJECT_PATH


class CalendarInterface(ServiceInterface):
    def __init__(self, service):
        super().__init__(INTERFACE)
        self.service = service
        self.busy = False

    @method()
    async def Read(self, action: "s", arguments: "s") -> "s":  # noqa: F821 - D-Bus signatures
        return await self.invoke(action, arguments, write=False)

    @method()
    async def Write(self, action: "s", arguments: "s") -> "s":  # noqa: F821 - D-Bus signatures
        return await self.invoke(action, arguments, write=True)

    async def invoke(self, action, arguments, *, write):
        if self.busy:
            return json.dumps(
                failure("BUSY", "Another calendar operation is running; retry shortly.")
            )
        self.busy = True
        try:
            return json.dumps(
                await asyncio.to_thread(
                    self.service.call, action, arguments, write=write
                )
            )
        finally:
            self.busy = False


async def serve(service):
    bus = await MessageBus().connect()
    try:
        bus.export(OBJECT_PATH, CalendarInterface(service))
        if (
            await bus.request_name(BUS_NAME, NameFlag.DO_NOT_QUEUE)
            != RequestNameReply.PRIMARY_OWNER
        ):
            raise PublicError(
                "BROKER_UNAVAILABLE",
                "Another calendar broker already owns the session bus name.",
            )
        await bus.wait_for_disconnect()
    finally:
        bus.disconnect()


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    try:
        asyncio.run(serve(CalendarService(Config.from_env())))
    except KeyboardInterrupt:
        pass
    except Exception:  # noqa: BLE001 - sanitize the process boundary
        # Never log configuration repr or raw exception strings.
        logging.getLogger(__name__).error(
            "Host broker failed. Check credentials, alias mapping and session bus."
        )
        raise SystemExit(1)


if __name__ == "__main__":
    main()
