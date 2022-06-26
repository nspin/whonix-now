let
  # HACK
  nixpkgs = builtins.getFlake "nixpkgs/${(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked.rev}";
  pkgs = import nixpkgs {};
  this = pkgs.callPackage ./whonix.nix {};
in this // { inherit pkgs; }
