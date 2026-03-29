{
  writeShellApplication,
  lib,
  fzf,
  jq,
  bat,
}:
let
  template-preview = writeShellApplication {
    name = "template-preview";
    text = lib.readFile ./template-preview.sh;
    runtimeInputs = [
      bat
      fzf
      jq
    ];
  };
in
writeShellApplication {
  name = "project-init";
  text = lib.readFile ./project-init.sh;
  runtimeInputs = [
    fzf
    jq
    template-preview
  ];
}
