{
  mozc,
  mozcdic-ut-alt-cannadic,
  mozcdic-ut-edict2,
  mozcdic-ut-jawiki,
  mozcdic-ut-neologd,
  mozcdic-ut-personal-names,
  mozcdic-ut-place-names,
  mozcdic-ut-skk-jisyo,
  mozcdic-ut-sudachidict,
}:
# Associated PR: https://github.com/NixOS/nixpkgs/pull/531687.
mozc.override {
  dictionaries = [
    mozcdic-ut-alt-cannadic
    mozcdic-ut-edict2
    mozcdic-ut-jawiki
    mozcdic-ut-neologd
    mozcdic-ut-personal-names
    mozcdic-ut-place-names
    mozcdic-ut-skk-jisyo
    mozcdic-ut-sudachidict
  ];
}
