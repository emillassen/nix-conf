{
  disko.devices = {
    disk = {
      nvme0n1 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "2048M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            #swap = { # Disabled until the system is to be installed, remember to change zramswap too
            #  size = "16G"; # Adjust based on your RAM
            #  content = {
            #    type = "swap";
            #    randomEncryption = true;
            #  };
            #};
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings.allowDiscards = true;
                passwordFile = "/tmp/secret.key";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
    };
  };
}
