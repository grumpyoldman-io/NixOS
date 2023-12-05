# NixOS

> [!WARNING]
> This is work in progress, please check if the TODO's are part of your requirements

This repo contains a set of configuration for installing
NixOS, using ZFS as (unencrypted) root filesystem.

## TODO

- [ ] Secrets management
- [ ] immutable users

## Installation

1. Create a boot USB for NixOS and boot in to the installer
1. Connect to the internet, and close the default installer wizard if you get that
1. Open Console (as sudo)

    ```sh
    sudo su
    ```

1. List available disks

    ```sh
    find /dev/disk/by-id/
    ```

1. Declare the disk (or array)

    ```sh
    DISK='/dev/disk/by-id/nvme-WD_RED_SN700_500GB_...'
    ```

1. Create a temporary mount point

    ```sh
    MNT=$(mktemp -d)
    ```

1. Enable Flakes

    ```sh
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
    ```

1. Install missing software

    ```sh
    if ! command -v git; then nix-env -f '<nixpkgs>' -iA git; fi
    if ! command -v jq;  then nix-env -f '<nixpkgs>' -iA jq; fi
    if ! command -v partprobe;  then nix-env -f '<nixpkgs>' -iA parted; fi
    ```

1. Partition Disk(s)

    ```sh
    partition_disk () {
      local disk="${1}"
      blkdiscard -f "${disk}" || true

      parted --script --align=optimal  "${disk}" -- \
      mklabel gpt \
      mkpart EFI 2MiB 1GiB \
      mkpart bpool 1GiB 5GiB \
      mkpart rpool 5GiB -1GiB \
      mkpart BIOS 1MiB 2MiB \
      set 1 esp on \
      set 4 bios_grub on \
      set 4 legacy_boot on

      partprobe "${disk}"
      udevadm settle
    }

    for i in ${DISK}; do
      partition_disk "${i}"
    done
    ```

1. Create boot pool (add `mirror` after bpool if you're using multiple drives)

    ```sh
    zpool create \
      -o compatibility=grub2 \
      -o ashift=12 \
      -o autotrim=on \
      -O acltype=posixacl \
      -O canmount=off \
      -O devices=off \
      -O normalization=formD \
      -O relatime=on \
      -O xattr=sa \
      -O mountpoint=/boot \
      -R "${MNT}" \
      bpool \
      $(for i in ${DISK}; do
        printf '%s ' "${i}-part2";
        done)
    ```

1. Create root pool (add `mirror` after rpool if you're using multiple drives)

    ```sh
    zpool create \
      -o ashift=12 \
      -o autotrim=on \
      -R "${MNT}" \
      -O acltype=posixacl \
      -O canmount=off \
      -O compression=zstd \
      -O dnodesize=auto \
      -O normalization=formD \
      -O relatime=on \
      -O xattr=sa \
      -O mountpoint=/ \
      rpool \
    $(for i in ${DISK}; do
        printf '%s ' "${i}-part3";
      done)
    ```

1. Create root system container

    ```sh
    zfs create \
      -o canmount=off \
      -o mountpoint=none \
    rpool/nixos
    ```

1. Create system datasets

    ```sh
    zfs create -o mountpoint=legacy rpool/nixos/root
    mount -t zfs rpool/nixos/root "${MNT}"/

    zfs create -o mountpoint=legacy rpool/nixos/home
    mkdir "${MNT}"/home
    mount -t zfs rpool/nixos/home "${MNT}"/home

    zfs create -o mountpoint=none   rpool/nixos/var
    zfs create -o mountpoint=legacy rpool/nixos/var/lib
    zfs create -o mountpoint=legacy rpool/nixos/var/log

    zfs create -o mountpoint=none bpool/nixos
    zfs create -o mountpoint=legacy bpool/nixos/root
    mkdir "${MNT}"/boot
    mount -t zfs bpool/nixos/root "${MNT}"/boot

    mkdir -p "${MNT}"/var/log
    mkdir -p "${MNT}"/var/lib

    mount -t zfs rpool/nixos/var/lib "${MNT}"/var/lib
    mount -t zfs rpool/nixos/var/log "${MNT}"/var/log
    zfs create -o mountpoint=legacy rpool/nixos/empty
    zfs snapshot rpool/nixos/empty@start
    ```

1. Format & Mount ESP

    ```sh
    for i in ${DISK}; do
      mkfs.vfat -n EFI "${i}"-part1
      mkdir -p "${MNT}"/boot/efis/"${i##*/}"-part1
      mount -t vfat -o iocharset=iso8859-1 "${i}"-part1 "${MNT}"/boot/efis/"${i##*/}"-part1
    done
    ```

1. Clone this Repo

    ```sh
    git clone https://github.com/grumpyoldman-io/NixOS.git "${MNT}"/etc/nixos
    ```

1. Set local Git config

    ```sh
    git -C "${MNT}"/etc/nixos config user.name "grumpyoldman-io"
    git -C "${MNT}"/etc/nixos config user.email "...@grumpyoldman.io"
    ```

1. Customize config to your hardware

    ```sh
    for i in ${DISK}; do
      sed -i \
      "s|/dev/disk/by-id/|${i%/*}/|" \
      "${MNT}"/etc/nixos/hosts/server/default.nix
      break
    done

    diskNames=""
    for i in ${DISK}; do
      diskNames="${diskNames} \"${i##*/}\""
    done

    sed -i "s|\"bootDevices_placeholder\"|${diskNames}|g" \
      "${MNT}"/etc/nixos/hosts/server/default.nix

    sed -i "s|\"abcd1234\"|\"$(head -c4 /dev/urandom | od -A none -t x4| sed 's| ||g' || true)\"|g" \
      "${MNT}"/etc/nixos/hosts/server/default.nix

    sed -i "s|\"x86_64-linux\"|\"$(uname -m || true)-linux\"|g" \
      "${MNT}"/etc/nixos/flake.nix
    ```

1. Detect kernel modules needed for boot

    ```sh
    cp "$(command -v nixos-generate-config || true)" ./nixos-generate-config

    chmod a+rw ./nixos-generate-config

    echo 'print STDOUT $initrdAvailableKernelModules' >> ./nixos-generate-config

    kernelModules="$(./nixos-generate-config --show-hardware-config --no-filesystems | tail -n1 || true)"

    sed -i "s|\"kernelModules_placeholder\"|${kernelModules}|g" \
      "${MNT}"/etc/nixos/hosts/server/default.nix
    ```

1. Set root (admin) password

    ```sh
    rootPwd=$(mkpasswd -m SHA-512)
    ```

    ```sh
    sed -i \
    "s|rootHash_placeholder|${rootPwd}|" \
    "${MNT}"/etc/nixos/configuration.nix
    ```

1. Update local git

    ```sh
    git -C "${MNT}"/etc/nixos commit -asm 'initial installation'
    ```

1. Update flake lock file to track latest system version

    ```sh
    nix flake update --commit-lock-file \
    "git+file://${MNT}/etc/nixos"
    ```

1. Install system and apply configuration

    ```sh
    nixos-install \
    --root "${MNT}" \
    --no-root-passwd \
    --flake "git+file://${MNT}/etc/nixos#server"
    ```

1. Unmount filesystems

    ```sh
    umount -Rl "${MNT}"
    zpool export -a
    ```

1. Reboot

    ```sh
    reboot
    ```

## ZFS

ZFS is a modern filesystem with many features such as snapshot,
self-healing and pooled storage, see [Introduction](https://openzfs.org/wiki/Main_Page#Introduction_to_OpenZFS) for details.

## Credits

This is based on the Openzfs Docs and there mentioned repository.
For using this repo on your computer, see [Documentation](https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html).
