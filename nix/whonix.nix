{ stdenv, lib, callPackage
, runCommand, writeText, writeScript, writeScriptBin, runtimeShell, buildEnv
, fetchurl
, nix, cacert
, qemu, libvirt, virt-manager, libguestfs-with-appliance
, gosu, xauth, dockerTools
, coreutils, gnugrep, gnused, iproute2, iptables
, bashInteractive
, pkgs
}:

let
  kaliWorkstation = false;
  enableSharedDirectories = true;
  enablePersistentImages = false;
  gatewayVcpus = 2;
  gatewayMemoryMegabytes = 4 * 1024;
  workstationVcpus = 6;
  workstationMemoryMegabytes = 16 * 1024;
in

let
  kali = callPackage ./kali.nix {};

  runtimeImagesDirectory = if enablePersistentImages then "/shared/container" else "/images";

  images =
    let
      xz = fetchurl {
        url = "https://download.whonix.org/libvirt/17.2.8.5/Whonix-Xfce-17.2.8.5.Intel_AMD64.qcow2.libvirt.xz";
        # url = "https://download.whonix.org/libvirt/17.3.9.9/Whonix-Xfce-17.3.9.9.Intel_AMD64.qcow2.libvirt.xz";
        sha256 = "e543fd662d465959937d626950bc9c5c86543a3b0559eb608b70c374f601a1af";
      };

      unpacked = runCommand "x" {
        nativeBuildInputs = [ qemu ];
      } ''
        mkdir $out
        tar -xvf ${xz} -C $out

        compress() {
          path=$1
          mv $path $path.sparse
          qemu-img convert -c -f qcow2 -O qcow2 $path.sparse $path
          rm $path.sparse
        }

        compress $(echo $out/Whonix-Gateway-*.qcow2)
        compress $(echo $out/Whonix-Workstation-*.qcow2)
      '';

      patched =
        let
          sharedDirectoryFragment = subdirectory:
            lib.replaceStrings [ "\n" ] [ "\\n" ] (lib.optionalString enableSharedDirectories ''
              <filesystem type='mount' accessmode='mapped'>
                <source dir='/shared/${subdirectory}'/>
                <target dir='shared'/>
              </filesystem>
            '');
        in
          runCommand "x" {
            nativeBuildInputs = [ qemu libguestfs-with-appliance ];
          } ''
            mkdir $out

            sed \
              -e "s,<blkiotune>,<!--," \
              -e "s,</blkiotune>,-->," \
              -e "s,<vcpu placement='static' cpuset='0'>1</vcpu>,<vcpu placement='static' cpuset='0'>${toString gatewayVcpus}</vcpu>," \
              -e "s,<memory dumpCore='off' unit='GB'>.*</memory>,<memory dumpCore='off' unit='KiB'>${toString (gatewayMemoryMegabytes * 1024)}</memory>," \
              -e "s,<currentMemory unit='GB'>.*</currentMemory>,," \
              -e "s,</devices>,${sharedDirectoryFragment "gateway"}</devices>," \
              -e "s,/var/lib/libvirt/images,${runtimeImagesDirectory}," \
              < ${unpacked}/Whonix-Gateway.xml > $out/Whonix-Gateway.xml

            sed \
              -e "s,<blkiotune>,<!--," \
              -e "s,</blkiotune>,-->," \
              -e "s,<vcpu placement='static' cpuset='1'>1</vcpu>,<vcpu placement='static' cpuset='1'>${toString workstationVcpus}</vcpu>," \
              -e "s,<memory dumpCore='off' unit='GB'>.*</memory>,<memory dumpCore='off' unit='KiB'>${toString (workstationMemoryMegabytes * 1024)}</memory>," \
              -e "s,<currentMemory unit='GB'>.*</currentMemory>,," \
              -e "s,</devices>,${sharedDirectoryFragment "workstation"}</devices>," \
              -e "s,/var/lib/libvirt/images,${runtimeImagesDirectory}," \
              < ${unpacked}/Whonix-Workstation.xml > $out/Whonix-Workstation.xml

            ln -s ${unpacked}/Whonix-Gateway-*.qcow2 $out/Whonix-Gateway.qcow2
            ln -s ${unpacked}/Whonix-Workstation-*.qcow2 $out/Whonix-Workstation.qcow2
          '';

      gatewayQcow2 = "${patched}/Whonix-Gateway.qcow2";
      workstationQcow2 = if kaliWorkstation then kali.vmQcow2 else "${patched}/Whonix-Workstation.qcow2";

      gatewayXml = "${patched}/Whonix-Gateway.xml";
      workstationXml = "${patched}/Whonix-Workstation.xml";

      internalNetworkXml = writeText "internal-network.xml" ''
        <network>
          <name>Whonix-Internal</name>
          <forward mode='bridge'/>
          <bridge name='vbrint' />
        </network>
      '';

      externalNetworkXml = writeText "external-network.xml" ''
        <network>
          <name>Whonix-External</name>
          <forward mode='bridge'/>
          <bridge name='vbrext' />
        </network>
      '';
    in {
      inherit xz unpacked patched;
      inherit gatewayQcow2 workstationQcow2 gatewayXml workstationXml internalNetworkXml externalNetworkXml;
    };

  scripts = with images;
    let
      xauthorityPath = "/home/x/Xauthority";

      refreshXauthority = writeScriptBin "refresh-xauthority" ''
        #!${runtimeShell}
        set -eu
        ${xauth}/bin/xauth -i -f /host.Xauthority nlist | ${gnused}/bin/sed -e 's/^..../ffff/' | ${xauth}/bin/xauth -f ${xauthorityPath} nmerge -
      '';

      interactScriptEnv = buildEnv {
        name = "env";
        paths = [
          coreutils
          gnugrep gnused
          iproute2 iptables
          bashInteractive
          nix cacert
          gosu
          qemu libvirt virt-manager
          refreshXauthority
        ] ++ (with pkgs; [
          strace
          inetutils
          ethtool
          # ...
        ]);
      };

      interactScript = writeScript "entry-continuation.sh" ''
        #!${runtimeShell}
        set -eu

        export PATH=${interactScriptEnv}/bin
        export MANPATH=${interactScriptEnv}/share/man
        export NIX_SSL_CERT_FILE=${interactScriptEnv}/etc/ssl/certs/ca-bundle.crt
        export XAUTHORITY=${xauthorityPath}

        bash
      '';

      entryScriptEnv = buildEnv {
        name = "env";
        paths = [
          coreutils
          iproute2 iptables
          gnugrep gnused
          qemu
        ];
      };

      entryScript = writeScript "entry.sh" ''
        #!${runtimeShell}
        set -eu

        export PATH=${entryScriptEnv}/bin:/run/wrappers/bin:$PATH

        # validate and process input
        : "''${HOST_GID:=100}"
        : "''${HOST_UID:=1000}"
        [ -n "$KVM_GID" ]
        [ -z "''${AUDIO_GID+x}" ] || [ -n "$AUDIO_GID"} ]

        ${dockerTools.shadowSetup}

        groupadd -g "$HOST_GID" x
        useradd -u "$HOST_UID" -g "$HOST_GID" -m x

        ensure_group() {
          group=$1
          gid=$2
          id -G x | if ! grep -q $gid; then
            groupadd -g $gid $group
            usermod -aG $group x
          fi
        }
        ensure_group kvm $KVM_GID
        if [ -n "''${AUDIO_GID+x}" ]; then
          ensure_group audio $AUDIO_GID
        fi

        ensure_user_dir() {
          if [ ! -d $1 ]; then
            mkdir -p $1
            chown x:x $1
          fi
        }

        shared_base=/shared
        shared_dirs="$shared_base/container $shared_base/gateway $shared_base/workstation"
        ensure_user_dir $shared_base
        for d in $shared_dirs; do
          ensure_user_dir $d
        done

        ensure_user_dir ${runtimeImagesDirectory}

        mkdir -p /run/wrappers/bin
        cp ${qemu}/libexec/qemu-bridge-helper /run/wrappers/bin
        chmod u+s /run/wrappers/bin/qemu-bridge-helper
        mkdir -p /etc/qemu
        touch /etc/qemu/bridge.conf

        ext_br_addr="10.0.2.2"
        ext_br_dev="vbrext"
        ip link add $ext_br_dev type bridge stp_state 1 forward_delay 0
        ip link set $ext_br_dev up
        ip addr add $ext_br_addr/24 dev $ext_br_dev
        iptables -t nat -F
        iptables -t nat -A POSTROUTING -s $ext_br_addr/24 ! -o $ext_br_dev -j MASQUERADE

        int_br_dev="vbrint"
        ip link add $int_br_dev type bridge stp_state 1 forward_delay 0
        ip link set $int_br_dev up

        echo "allow $ext_br_dev" >> /etc/qemu/bridge.conf
        echo "allow $int_br_dev" >> /etc/qemu/bridge.conf

        mkdir -p /etc/nix
        ln -s ${./nix.conf} /etc/nix/nix.conf

        ${gosu}/bin/gosu x ${entryScriptContinuation}
      '';

      entryScriptContinuation = writeScript "entry-continuation.sh" ''
        #!${runtimeShell}
        set -eu

        touch ${xauthorityPath}
        ${refreshXauthority}/bin/refresh-xauthority

        ensure_image() {
          if [ ! -f ${runtimeImagesDirectory}/$2 ]; then
            ${qemu}/bin/qemu-img create -f qcow2 -o backing_fmt=qcow2 -o backing_file=$1 ${runtimeImagesDirectory}/$2
          fi
        }

        ensure_image ${gatewayQcow2} Whonix-Gateway.qcow2
        ensure_image ${workstationQcow2} Whonix-Workstation.qcow2

        virsh_c() {
          ${libvirt}/bin/virsh -c qemu:///session "$@"
        }

        virsh_c net-define ${internalNetworkXml}
        virsh_c net-autostart Whonix-Internal
        virsh_c net-start Whonix-Internal
        virsh_c net-define ${externalNetworkXml}
        virsh_c net-autostart Whonix-External
        virsh_c net-start Whonix-External
        virsh_c define ${gatewayXml}
        virsh_c define ${workstationXml}

        XAUTHORITY=${xauthorityPath} ${virt-manager}/bin/virt-manager -c qemu:///session

        echo "Initialization complete. Sleeping..."
        sleep inf
      '';

    in {
      inherit refreshXauthority;
      inherit entryScript interactScript;
    };

  selfContainedImage = dockerTools.buildImage {
    name = "whonix-now";
    tag = "0.0.1";

    runAsRoot = ''
      #!${stdenv.shell}
      ${coreutils}/bin/ln -s ${scripts.interactScript} /interact
      ${coreutils}/bin/ln -s ${scripts.refreshXauthority}/bin/refresh-xauthority /
    '';

    config = {
      Cmd = [ scripts.entryScript ];
    };
  };

in {
  inherit images scripts kali;
  inherit (scripts) entryScript interactScript;
  inherit selfContainedImage;
}
