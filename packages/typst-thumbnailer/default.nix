{ writeShellScript
, writeTextFile
, runCommand
, typst
, lib
}:
let
  script = writeShellScript "typst2png" ''
    TMP=/tmp/typst2png/$(basename $1)
    mkdir -p $TMP
    ${lib.getExe typst} compile --format png $1 $TMP/output{n}.png
    cp $TMP/output1.png $2
    rm -r $TMP
  '';
  thumbnailer = writeTextFile {
    name = "typst.thumbnailer";
    text = ''
      [Thumbnailer Entry]
      Exec=${placeholder "out"}/bin/typst2png %i %o
      MimeType=text/x-typst
    '';
  };
in
runCommand "typst-thumbnailer" { } ''
  mkdir -pv $out/{share/thumbnailers,bin}
  cp -v ${script} $out/bin/typst2png
  cp -v ${thumbnailer} $out/share/thumbnailers/typst.thumbnailer
''
