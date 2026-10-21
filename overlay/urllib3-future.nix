{
  flake.overlays.urllib3-future = final: prev: {
    # Skip SOCKS tests incompatible with python-socks v3.
    # Track the contents of https://github.com/NixOS/nixpkgs/pull/575392 and
    # https://github.com/jawah/urllib3.future/issues/437.
    # Issue #437 closed with 2.25.903, but that release still caps python-socks
    # at <=2.8.1; it does not fix v3 runtime compatibility. Release details:
    # https://github.com/jawah/urllib3.future/pull/438
    # Remove once the pinned nixpkgs includes the test exclusions or an upstream fix.
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pythonFinal: pythonPrev: {
        urllib3-future = pythonPrev.urllib3-future.overridePythonAttrs (oldAttrs: {
          disabledTestPaths = (oldAttrs.disabledTestPaths or [ ]) ++ [
            "test/contrib/asynchronous/test_socks.py"
            "test/contrib/test_socks.py"
          ];
        });
      })
    ];
  };
}
