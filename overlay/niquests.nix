{
  flake.overlays.niquests = final: prev: {
    # niquests' proxy-environment test exercises urllib3-future's SOCKS support,
    # which is incompatible with python-socks v3. All eight variants fail before
    # sending any SOCKS data; keep the rest of the test suite enabled.
    # Track https://github.com/jawah/urllib3.future/issues/437 and the pinned
    # nixpkgs niquests expression. This complements urllib3-future.nix's skips;
    # it does not repair SOCKS runtime support.
    # Remove once nixpkgs excludes this test or upstream supports python-socks v3.
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pythonFinal: pythonPrev: {
        niquests = pythonPrev.niquests.overridePythonAttrs (oldAttrs: {
          disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_use_proxy_from_environment" ];
        });
      })
    ];
  };
}
