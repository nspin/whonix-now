{ callPackage
}:

let

  mkWhonix = callPackage ./whonix.nix {};

in {

  whonix = mkWhonix {};

  kali = mkWhonix {
    kaliWorkstation = true;
  };

}
