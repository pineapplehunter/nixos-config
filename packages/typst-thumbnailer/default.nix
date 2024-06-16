{ runCommand
, typst
, lib
}:
runCommand "typst-thumbnailer"
{
  script = ''
    TMP=/tmp/typst2png/$(basename $1)
    mkdir -p $TMP
    ${lib.getExe typst} compile --format png $1 $TMP/output{n}.png
    cp $TMP/output1.png $2
    rm -r $TMP
  '';
  thumbnailer = ''
    [Thumbnailer Entry]
    Exec=${placeholder "out"}/bin/typst2png %i %o
    MimeType=text/x-typst
  '';
  passAsFile = [ "script" "thumbnailer" ];
} ''
  mkdir -pv $out/{share/thumbnailers,bin}
  cp -v $scriptPath $out/bin/typst2png
  cp -v $thumbnailerPath $out/share/thumbnailers/typst.thumbnailer
''
