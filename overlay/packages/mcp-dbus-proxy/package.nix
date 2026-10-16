{
  lib,
  python3Packages,
  dbus,
  xdg-dbus-proxy,
  nss_wrapper,
}:
python3Packages.buildPythonApplication {
  pname = "mcp-dbus-proxy";
  version = "0.1.0";
  pyproject = true;
  src = lib.cleanSource ./.;
  build-system = [ python3Packages.hatchling ];
  dependencies = [ python3Packages.dbus-next ];
  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    python3Packages.mcp
    dbus
    xdg-dbus-proxy
  ];
  env.MCP_TEST_NSS_WRAPPER = "${nss_wrapper}/lib/libnss_wrapper.so";
  pythonImportsCheck = [
    "mcp_dbus_proxy.client"
    "mcp_dbus_proxy.host"
  ];
  meta = {
    description = "MCP stdio bridge to host-side servers over filtered D-Bus";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "mcp-dbus-proxy";
  };
}
