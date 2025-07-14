{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        inherit pkgs;

        packages = pkgs.callPackage ./whonix.nix {};

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            # ...
          ];
        };
      }
    );
}
