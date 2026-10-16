{
  lib,
  python3Packages,
  dbus,
  xdg-dbus-proxy,
  nss_wrapper,
  mcp-dbus-proxy,
}:

python3Packages.buildPythonApplication {
  pname = "radicale-agent";
  version = "0.2.0";
  pyproject = true;
  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: type:
      let
        name = baseNameOf path;
      in
      !(builtins.elem name [
        ".venv"
        ".pytest_cache"
        "__pycache__"
        ".env"
        "credentials.json"
      ]);
  };

  build-system = [ python3Packages.hatchling ];
  # Runtime versions are provided reproducibly by the repository's flake.lock.
  # uv.lock separately locks the standalone Python development environment.
  dependencies = with python3Packages; [
    caldav
    icalendar
    mcp
    pydantic
  ];
  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
    pytest-asyncio
    dbus-next
    mcp-dbus-proxy
    dbus
    xdg-dbus-proxy
    nss_wrapper
  ];
  # Used only when a minimal test environment has no passwd entry for its UID.
  env.RADICALE_TEST_NSS_WRAPPER = "${nss_wrapper}/lib/libnss_wrapper.so";
  pythonImportsCheck = [
    "radicale_agent.service"
    "radicale_agent.server"
  ];

  meta = {
    description = "Standalone MCP server restricted to the Agent CalDAV collection";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "radicale-agent-mcp";
  };
}
