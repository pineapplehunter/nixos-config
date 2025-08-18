let
  action-shogo = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM/QhUXk6LPpFd97zUow1bHkkF1CvRAjCG1iIfg5BBhd";
  beast-shogo = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4374jhuKtCRAl0oUFRyWhBw1CoPjRved9KwhFCP0MW";
  kpro-takata-takata = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII9nG2lTRf+GAA92Df7yTbxPmL3EMNMgVr5tIv3YgJI7 takata@kpro-takata";
  users = [
    action-shogo
    beast-shogo
    kpro-takata-takata
  ];

  action-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL9EgqwqmPrBTUtPTBklXlZRSpTXiAycUdzRQ4NTxKd9";
  beast-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGON5XWNu4X8mWHIH0YkcYha4PH0ykL2PdlF7R8Gl0T/";
  kpro-takata-system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIANSMl7jstvPFct/CSJ3UD/zLTqKFLHJOQUt7TeHsKI root@kpro-takata";
  systems = [
    action-system
    beast-system
    kpro-takata-system
  ];
in
{
  "access-tokens.age".publicKeys = users ++ systems;
  "geesefs-creds.age".publicKeys = users ++ [ beast-system ];
  "garage-secret.age".publicKeys = users ++ systems;
}
