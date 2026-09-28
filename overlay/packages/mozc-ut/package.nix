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
# Keep nixpkgs' eight UT dictionaries with the local split Mozc package: the
# pinned nixpkgs wrapper still passes the removed withIbus argument.
# Associated PR: https://github.com/NixOS/nixpkgs/pull/531687.
# Drop this when nixpkgs' mozc-ut supports the split package without withIbus.
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
