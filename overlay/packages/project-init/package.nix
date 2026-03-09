{
  writeShellApplication,
  lib,
  fzf,
  jq,
}:
writeShellApplication {
  name = "project-init";
  text = lib.readFile ./project-init.sh;
  runtimeInputs = [
    fzf
    jq
  ];
}
