{ config, lib, pkgs, ... }: {
  imports = [
    ./boot
    ./fileSystems
    ./home-assistant
  ];
}
