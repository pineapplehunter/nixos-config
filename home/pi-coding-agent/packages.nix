{
  pkgs,
  lib,
  inputs,
}:
let
  anthropicSkillNames = [
    "algorithmic-art"
    "canvas-design"
    "discernment-nudge"
    "doc-coauthoring"
    "docx"
    "frontend-design"
    "internal-comms"
    "pdf"
    "pptx"
    "theme-factory"
    "webapp-testing"
    "xlsx"
  ];

  anthropicSkills = pkgs.runCommand "anthropic-skills" { } ''
    mkdir -p "$out/skills"
    cp ${./anthropic-skills/package.json} "$out/package.json"
    for skill in ${lib.escapeShellArgs anthropicSkillNames}; do
      cp -R "${inputs.anthropic-skills}/skills/$skill" "$out/skills/"
    done
  '';
in
[
  # Interpolation imports the ready-to-load directory into the Nix store.
  "${./pineapplehunter}"
  anthropicSkills
]
