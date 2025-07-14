let
  # HACK
  nixpkgs = builtins.getFlake "nixpkgs/${(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked.rev}";
  pkgs = import nixpkgs {};
  this = pkgs.callPackage ./configs.nix {};
in this // { inherit pkgs; }
