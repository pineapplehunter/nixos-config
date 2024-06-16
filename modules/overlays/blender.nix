{ final, prev, ... }:
let
  python = final.python311Packages;
  inherit (prev.blender) pname version;
in
{
  blender = final.symlinkJoin {
    name = "${pname}-wrapped-${version}";
    paths = [ prev.blender ];
    nativeBuildInputs = [
      final.makeWrapper
      python.wrapPython
    ];
    pythonPath = with python; [ numpy requests py-slvs ];
    postBuild = ''
      rm $out/bin/blender
      mv $out/bin/.blender-wrapped $out/bin/blender

      buildPythonPath "$pythonPath"
      wrapProgram $out/bin/blender \
        --prefix PATH : $program_PATH \
        --prefix PYTHONPATH : "$program_PYTHONPATH" \
        --add-flags "--python-use-system-env"
    '';
  };
}
