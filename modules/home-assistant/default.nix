{ pkgs, ... }: {
  services.home-assistant = {
    enable = true;
    configDir = /var/lib/home-assistant;
    package = (pkgs.home-assistant.override {
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/home-assistant/component-packages.nix
      extraComponents = [
        "default_config"
        "esphome"
        "met"
      ];
      extraPackages = ps: with ps; [
        # Are you using a database server for your recorder?
        # https://www.home-assistant.io/integrations/recorder/
        #mysqlclient
        #psycopg2
      ];
    });
  };
}
