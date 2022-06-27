# [Whonix](https://www.whonix.org/) with KVM in Linux containers

`DOCUMENTATION UNDER CONSTRUCTION`

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
