{ lib, runCommand, writeText
, fetchurl
, qemu, libguestfs-with-appliance
}:

let
  persistenceSize = "64G";
in

let
  images =
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

        # read from ro partition, write to rw overlay

        fname1=interfaces
        dir1=/etc/network
        path1=$dir1/$fname1
        fname2=resolv.conf 
        dir2=/etc
        path2=$dir2/$fname2
        fname3=live.cfg
        dir3=/isolinux
        path3=$dir3/$fname3

        guestfish --ro <<EOF
        add $img
        run
        mkmountpoint /parent
        mkmountpoint /child
        mount /dev/sda1 /parent
        mount-loop /parent/live/filesystem.squashfs /child
        copy-out /child$path1 .
        copy-out /child$path2 .
        copy-out /parent$path3 .
        umount /child
        EOF

        cat ${appendInterfaces} >> $fname1
        cat ${appendResolveConf} >> $fname2

        sed -i \
          -e 's,append boot=live username=kali hostname=kali persistence,append boot=live username=kali hostname=kali persistence ip=frommedia,' \
          $fname3

        guestfish <<EOF
        add $img
        run
        mkmountpoint /live
        mkmountpoint /persistence
        mount /dev/sda1 /live
        mount /dev/sda3 /persistence
        mkdir-p /persistence/rw$dir1
        copy-in $fname1 /persistence/rw$dir1
        mkdir-p /persistence/rw$dir2
        copy-in $fname2 /persistence/rw$dir2
        mkdir-p /live$dir3
        copy-in $fname3 /live$dir3
        EOF

        rm $fname1
        rm $fname2

        mv $img $out
      '';

      appendInterfaces = writeText "x" ''
        auto eth0
        iface eth0 inet static
          address 10.152.152.11
          netmask 255.255.192.0
          gateway 10.152.152.10
      '';

      appendResolveConf = writeText "x" ''
        nameserver 10.152.152.10
      '';

    in {
      inherit iso vmQcow2;
    };

in {
  inherit images;
}
