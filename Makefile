shared_base := shared
shared_dirs := $(addprefix $(shared_base)/,container workstation gateway)

universal_name := whonix-demo

label := $(universal_name)
image_repository := $(universal_name)
image_tag := $(image_repository)
container_name := $(universal_name)
dockerfile := Dockerfile

host_uid := $(shell id -u)
host_gid := $(shell id -g)
kvm_gid := $(shell stat -c '%g' /dev/kvm)
audio_gid := $(shell stat -c '%g' /dev/snd/timer) # HACK is this portable?

entry_script_fragment := $$(nix-build nix -A entryScript)
interact_script_fragment := $$(nix-build nix -A interactScript)

.PHONY: none
none:

$(shared_dirs):
	mkdir -p $@

.PHONY: build
build:
	docker build \
		--label $(label) -t $(image_tag) -f $(dockerfile) .

.PHONY: run
run: build | $(shared_dirs)
	docker run -d -it --name $(container_name) --label $(label) \
		--cap-add=NET_ADMIN \
		--tmpfs /tmp \
		--device /dev/kvm \
		--device /dev/net/tun \
		--device /dev/snd \
		--mount type=bind,src=/nix/store,dst=/nix/store,ro \
		--mount type=bind,src=/nix/var/nix/db,dst=/nix/var/nix/db,ro \
		--mount type=bind,src=/nix/var/nix/daemon-socket,dst=/nix/var/nix/daemon-socket,ro \
		--mount type=bind,src=/tmp/.X11-unix,dst=/tmp/.X11-unix,ro \
		--mount type=bind,src=$(XAUTHORITY),dst=/host.Xauthority,ro \
		--mount type=bind,src=$(abspath $(shared_base)),dst=/shared \
		--env HOST_UID=$(host_uid) \
		--env HOST_GID=$(host_gid) \
		--env KVM_GID=$(kvm_gid) \
		--env AUDIO_GID=$(audio_gid) \
		--env DISPLAY \
		$(image_tag) \
		$(entry_script_fragment)

.PHONY: exec
exec:
	docker exec -it \
		--user $(host_uid) \
		--env DISPLAY \
		$(container_name) \
		$(interact_script_fragment)

.PHONY: exec-as-root
exec-as-root:
	docker exec -it \
		--env DISPLAY \
		$(container_name) \
		$(interact_script_fragment)

.PHONY: rm-container
rm-container:
	for id in $$(docker ps -aq -f "name=^$(container_name)$$"); do \
		docker rm -f $$id; \
	done

.PHONY: show-logs
show-logs:
	for id in $$(docker ps -aq -f "name=^$(container_name)$$"); do \
		docker logs $$id; \
	done

###

.PHONY: self-contained-image-build
self-contained-image-build:
	docker load -i $$(nix-build nix -A selfContainedImage)

.PHONY: self-contained-image-run
self-contained-image-run: | $(shared_dirs)
	docker run -d -it --name $(container_name) --label $(label) \
		--cap-add=NET_ADMIN \
		--tmpfs /tmp \
		--device /dev/kvm \
		--device /dev/net/tun \
		--device /dev/snd \
		--mount type=bind,src=/tmp/.X11-unix,dst=/tmp/.X11-unix,ro \
		--mount type=bind,src=$(XAUTHORITY),dst=/host.Xauthority,ro \
		--mount type=bind,src=$(abspath $(shared_base)),dst=/shared \
		--env HOST_UID=$(host_uid) \
		--env HOST_GID=$(host_gid) \
		--env KVM_GID=$(kvm_gid) \
		--env AUDIO_GID=$(audio_gid) \
		--env DISPLAY \
		whonix-now:0.0.1

.PHONY: self-contained-image-exec
self-contained-image-exec:
	docker exec -it \
		--user $(host_uid) \
		--env DISPLAY \
		$(container_name) \
		/interact

.PHONY: self-contained-image-exec-as-root
self-contained-image-exec-as-root:
	docker exec -it \
		--env DISPLAY \
		$(container_name) \
		/interact
