# [Whonix](https://www.whonix.org/) on KVM in Linux containers

This repository contains a collection of [Nix](https://nixos.org/) expressions and shell scripts for running [Whonix](https://www.whonix.org/) virtual machines on KVM via [libvirt](https://libvirt.org/) inside of Docker containers. Docker serves to simplify the configuration and management of the network and filesystem resources associated with Whonix virtual machines.

```
!!! WARNING !!!

This repository includes a patch [1] to the Whonix-Gateway firewall to work
around an unresolved libvirt-related networking issue.

Do not use this repository for anonymization unless you understand the
consequences of both this patch and the mere fact of its presence.

[1] ./nix/whonix.nix#80
```

## Quickstart

No need to clone this repository.

First, install [Nix](https://nixos.org/download.html).

Then, run:

```sh
echo "FROM scratch" | docker build --label whonix-now-demo -t whonix-now-demo -f - .

docker run --rm -it --name whonix-now-demo --label whonix-now-demo \
    --cap-add=NET_ADMIN \
    --device /dev/kvm \
    --device /dev/net/tun \
    --mount type=bind,src=/nix/store,dst=/nix/store,ro \
    --mount type=bind,src=/tmp/.X11-unix,dst=/tmp/.X11-unix,ro \
    --mount type=bind,src=$XAUTHORITY,dst=/host.Xauthority,ro \
    --env KVM_GID=$(stat -c '%g' /dev/kvm) \
    --env DISPLAY \
    whonix-now-demo \
    $(nix build 'github:nspin/whonix-now?dir=nix#entryScript' --print-out-paths \
        --extra-experimental-features nix-command --extra-experimental-features flakes)
```
