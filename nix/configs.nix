{ callPackage
}:

let

  mkWhonix = callPackage ./whonix.nix {};

  mkBigConfig = kali: rec {
    workstationName = if kali then "kali" else "whonix";
    enablePersistentImages = false;
    workstationVcpus = if kali then 8 else 4;
    workstationMemoryMegabytes = workstationVcpus * 2 * 1024;
    enableWorkstationSharedDirectory = true;
  };

in rec {

  stock = mkWhonix {};

  big = mkWhonix (mkBigConfig "whonix");

  kali = mkWhonix (mkBigConfig "kali");

  default = mkWhonix {
    enableWorkstationSharedDirectory = true;
  };

}
