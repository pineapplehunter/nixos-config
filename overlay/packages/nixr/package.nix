{
  writeShellApplication,
  lib,
}:
writeShellApplication {
  name = "nixr";
  text = lib.readFile ./nixr.sh;
  runtimeInputs = [ ];
}
