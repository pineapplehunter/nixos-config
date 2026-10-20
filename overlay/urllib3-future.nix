{
  flake.overlays.urllib3-future = final: prev: {
    # Skip SOCKS tests incompatible with python-socks v3.
    # Track the contents of https://github.com/NixOS/nixpkgs/pull/575392 and
    # https://github.com/jawah/urllib3.future/issues/437.
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
