"""Public errors never contain exception text, URLs, or HTTP bodies."""


class PublicError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(code)

    def response(self) -> dict:
        return {"ok": False, "error": {"code": self.code, "message": self.message}}


def failure(code: str, message: str) -> dict:
    return PublicError(code, message).response()
