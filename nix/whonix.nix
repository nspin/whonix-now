{ stdenv, lib, runCommand, writeText, writeScript, writeScriptBin, runtimeShell, buildEnv
, fetchurl
, nix, cacert
, qemu, libvirt, virt-manager, libguestfs-with-appliance
, gosu, xauth, dockerTools
, coreutils, gnugrep, gnused, iproute2, iptables
, bashInteractive
, pkgs
}:

let
  gatewayMemoryMegabytes = 2048;
  workstationMemoryMegabytes = 2048;
in

let
  images =
    let
      xz = fetchurl {
        url = "https://download.whonix.org/libvirt/16.0.5.3/Whonix-XFCE-16.0.5.3.Intel_AMD64.qcow2.libvirt.xz";
        hash = "sha256-h1fmeZKG1s0VC4ydoj98ed9mR61RKNZVBCE38XZG26Q=";
      };

      unpacked = runCommand "x" {
        nativeBuildInputs = [ qemu ];
      } ''
        mkdir $out
        tar -xvf ${xz} -C $out

        x=$(echo $out/Whonix-Gateway-*.qcow2)
        mv $x $x.sparse
        qemu-img convert -c -f qcow2 -O qcow2 $x.sparse $x
        rm $x.sparse

        x=$(echo $out/Whonix-Workstation-*.qcow2)
        mv $x $x.sparse
        qemu-img convert -c -f qcow2 -O qcow2 $x.sparse $x
        rm $x.sparse
      '';

      patched =
        let
          sharedDirectoryFragment = subdirectory: lib.replaceChars [ "\n" ] [ "\\n" ] ''
            <filesystem type='mount' accessmode='mapped'>
              <source dir='/shared/${subdirectory}'/>
              <target dir='shared'/>
            </filesystem>
          '';
        in
          runCommand "x" {
            nativeBuildInputs = [ qemu libguestfs-with-appliance ];
          } ''
            mkdir $out

            sed \
              -e 's,<blkiotune>,<!--,' \
              -e 's,</blkiotune>,-->,' \
              -e "s,<memory dumpCore='off' unit='KiB'>.*</memory>,<memory dumpCore='off' unit='KiB'>${toString (gatewayMemoryMegabytes * 1024)}</memory>," \
              -e "s,<currentMemory unit='KiB'>.*</currentMemory>,," \
              -e "s,</devices>,${sharedDirectoryFragment "gateway"}</devices>," \
              < ${unpacked}/Whonix-Gateway-*.xml > $out/Whonix-Gateway.xml

            sed \
              -e 's,<blkiotune>,<!--,' \
              -e 's,</blkiotune>,-->,' \
              -e "s,<memory dumpCore='off' unit='KiB'>.*</memory>,<memory dumpCore='off' unit='KiB'>${toString (workstationMemoryMegabytes * 1024)}</memory>," \
              -e "s,<currentMemory unit='KiB'>.*</currentMemory>,," \
              -e "s,</devices>,${sharedDirectoryFragment "workstation"}</devices>," \
              < ${unpacked}/Whonix-Workstation-*.xml > $out/Whonix-Workstation.xml

            ln -s ${unpacked}/Whonix-Workstation-*.qcow2 $out/Whonix-Workstation.qcow2

            # HACK
            # https://forums.whonix.org/t/have-firewall-accept-icmp-fragmentation-needed/10233

            new=$out/Whonix-Gateway.qcow2
            ${qemu}/bin/qemu-img create -f qcow2 -o backing_fmt=qcow2 -o backing_file=$(echo ${unpacked}/Whonix-Gateway-*.qcow2) $new

            fname=50_user.conf
            dir=/etc/whonix_firewall.d
            path=$dir/$fname
            guestfish add $new : run : mount /dev/sda1 / : copy-out $path .
            echo GATEWAY_ALLOW_INCOMING_ICMP=1 >> $fname
            guestfish add $new : run : mount /dev/sda1 / : copy-in $fname $dir

            fname=whonix-gateway-firewall
            dir=/usr/bin
            path=$dir/$fname
            guestfish add $new : run : mount /dev/sda1 / : copy-out $path .
            sed -i \
              's,\$iptables_cmd -A INPUT -p icmp -j DROP,$iptables_cmd -A INPUT -p icmp -j DROP; else $iptables_cmd -A INPUT -p icmp --icmp-type destination-unreachable -m state --state RELATED -j ACCEPT,' \
              $fname
            guestfish add $new : run : mount /dev/sda1 / : copy-in $fname $dir : chown 0 0 $path : chmod 0755 $path
          '';

      gatewayQcow2 = "${patched}/Whonix-Gateway.qcow2";
      workstationQcow2 = "${patched}/Whonix-Workstation.qcow2";

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

      runtimeImagesDir = "/var/lib/libvirt/images";

      entryScript = writeScript "entry.sh" ''
        #!${runtimeShell}
        set -eu

        export PATH=${entryScriptEnv}/bin:$PATH

        ${dockerTools.shadowSetup}

        : ''${HOST_GID:=100}
        : ''${HOST_UID:=1000}

        groupadd -g "$HOST_GID" x
        useradd -u "$HOST_UID" -g "$HOST_GID" -m x
        id -G x | if ! grep -q $KVM_GID; then
          groupadd -g "$KVM_GID" kvm
          usermod -aG kvm x
        fi
        if [ ! -z ''${AUDIO_GID+x} ]; then
          id -G x | if ! grep -q $AUDIO_GID; then
            groupadd -g "$AUDIO_GID" audio
            usermod -aG audio x
          fi
        fi

        mkdir -p /etc/nix
        ln -s ${./nix.conf} /etc/nix/nix.conf

        shared_base=/shared
        shared_dirs="$shared_base/container $shared_base/gateway $shared_base/workstation"
        if [ ! -d $shared_base ]; then
          mkdir -p $shared_dirs
          chown x:x $shared_dirs
        fi

        mkdir -p ${runtimeImagesDir}
        chown x:x ${runtimeImagesDir}

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

        ${gosu}/bin/gosu x ${entryScriptContinuation}
      '';

      entryScriptContinuation = writeScript "entry-continuation.sh" ''
        #!${runtimeShell}
        set -eu

        touch ${xauthorityPath}
        ${refreshXauthority}/bin/refresh-xauthority

        create_shallow() {
          ${qemu}/bin/qemu-img create -f qcow2 -o backing_fmt=qcow2 -o backing_file=$1 ${runtimeImagesDir}/$2
        }

        create_shallow ${gatewayQcow2} Whonix-Gateway.qcow2
        create_shallow ${workstationQcow2} Whonix-Workstation.qcow2

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
  inherit images scripts;
  inherit (scripts) entryScript interactScript;
  inherit selfContainedImage;
}
