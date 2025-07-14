SHARED ?= ../shared

ifeq ($(KALI),1)
	config := kali
else
	config := whonix
endif

universal_name := whonix-now-$(config)

label := $(universal_name)
image_repository := $(universal_name)
image_tag := $(image_repository)
container_name := $(universal_name)
dockerfile := Dockerfile

shared_dir := $(SHARED)

host_uid := $(shell id -u)
host_gid := $(shell id -g)
kvm_gid := $(shell stat -c '%g' /dev/kvm)
audio_gid := $(shell stat -c '%g' /dev/snd/timer)

entry_script_fragment := $$(nix-build nix -A $(config).entryScript)
interact_script_fragment := $$(nix-build nix -A $(config).interactScript)

common_docker_run_args := \
	--cap-add=NET_ADMIN \
	--tmpfs /tmp \
	--device /dev/kvm \
	--device /dev/net/tun \
	--device /dev/snd \
	--mount type=bind,src=/tmp/.X11-unix,dst=/tmp/.X11-unix,ro \
	--mount type=bind,src=$(XAUTHORITY),dst=/host.Xauthority,ro \
	--mount type=bind,src=$(abspath $(shared_dir)),dst=/shared \
	--env HOST_UID=$(host_uid) \
	--env HOST_GID=$(host_gid) \
	--env KVM_GID=$(kvm_gid) \
	--env AUDIO_GID=$(audio_gid) \
	--env DISPLAY

.PHONY: none
none:

$(shared_dir):
	mkdir -p $@

.PHONY: rm-shared
rm-shared:
	rm -rf $(shared_dir)

.PHONY: build
build:
	docker build \
		--label $(label) -t $(image_tag) -f $(dockerfile) /var/empty

.PHONY: run
run: build | $(shared_dir)
	docker run -d -it --name $(container_name) --label $(label) \
		$(common_docker_run_args) \
		--mount type=bind,src=/nix/store,dst=/nix/store,ro \
		--mount type=bind,src=/nix/var/nix/db,dst=/nix/var/nix/db,ro \
		--mount type=bind,src=/nix/var/nix/daemon-socket,dst=/nix/var/nix/daemon-socket,ro \
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
	docker load -i $$(nix-build nix -A $(config).selfContainedImage)

.PHONY: self-contained-image-run
self-contained-image-run: | $(shared_dir)
	docker run -d -it --name $(container_name) --label $(label) \
		$(common_docker_run_args) \
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
