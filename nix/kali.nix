{ lib, runCommand, writeText
, fetchurl
, qemu, libguestfs-with-appliance
}:

let
  persistenceSize = "64G";
in

let
  iso = fetchurl {
    url = "https://cdimage.kali.org/kali-2022.2/kali-linux-2022.2-live-amd64.iso";
    hash = "sha256-7uTqtgOxCgYY4ZABWcuRuJab8TEH5dg0OB7LIaVg4Uk=";
  };

  vmQcow2 = runCommand "kali-live-persistent.qcow2" {
    nativeBuildInputs = [ qemu libguestfs-with-appliance ];
  } ''
    img=new.qcow2

    qemu-img create -f qcow2 -o backing_fmt=raw -o backing_file=${iso} $img
    qemu-img resize -f qcow2 $img +${persistenceSize}

    last_byte=$(
      guestfish add $img : run : part-list /dev/sda | \
        sed -rn 's,^  part_end: ([0-9]+)$,\1,p' | sort | tail -n 1
    )

    sector_size=$(
      guestfish add $img : run : blockdev-getss /dev/sda
    )

    first_sector=$(expr $(expr $last_byte + 1) / $sector_size)

    cat > persistence.conf <<EOF
    / union
    EOF

    guestfish <<EOF
    add $img
    run
    part-add /dev/sda primary $first_sector -1
    mkfs ext4 /dev/sda3 label:persistence
    mount /dev/sda3 /
    copy-in persistence.conf /
    EOF

    guestfish --ro <<EOF
    add $img
    run
    mkmountpoint /parent
    mkmountpoint /child
    mount /dev/sda1 /parent
    mount-loop /parent/live/filesystem.squashfs /child
    copy-out /child/etc/NetworkManager/NetworkManager.conf .
    umount /child
    EOF

    cp ${resolvConf} resolv.conf
    cat ${appendNetworkManagerConf} >> NetworkManager.conf
    cp ${rcLocal} rc.local

    guestfish <<EOF
    add $img
    run
    mount /dev/sda3 /
    mkdir-p /rw/etc/NetworkManager
    copy-in resolv.conf /rw/etc
    copy-in NetworkManager.conf /rw/etc/NetworkManager
    copy-in rc.local /rw/etc
    chmod 0755 /rw/etc/rc.local
    EOF

    mv $img $out
  '';

  resolvConf = writeText "x" ''
    nameserver 10.152.152.10
  '';

  appendNetworkManagerConf = writeText "x" ''
    [keyfile]
    unmanaged-devices=*
  '';

  # HACK
  # Ideally we'd be able to just statically append to
  # /etc/network/interfaces at built time, but the live image has some awful
  # scripts which overwrite that file a each boot. See
  # /lib/live/boot/9990-netbase.sh:38. According to these scripts, we could
  # prevent that behavior with a kernel cmdline parameter, but this gross
  # /etc/rc.local hack has the advantage of only affecting the persistence
  # partition.
  rcLocal = writeText "x" ''
    #!/bin/sh

    cat >> /etc/network/interfaces <<EOF
    iface eth0 inet static
      address 10.152.152.11
      netmask 255.255.192.0
      gateway 10.152.152.10
    EOF

    ifup eth0
  '';

in {
  inherit iso vmQcow2;
}
