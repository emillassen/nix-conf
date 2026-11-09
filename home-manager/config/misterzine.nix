# MisterZine Jellyfin on the MiSTer Pi. misterzine-jellyfin-update (pkgs/)
# builds each new release from public source and installs it over SSH; the
# timer below checks for one every hour. Key login to the MiSTer is set up once
# with `misterzine-jellyfin-update --setup-ssh` (asks the MiSTer's root
# password), and again after a MiSTer Linux update, which drops the key — the
# timer sends a notification when that happens.
{ lib, pkgs, ... }:
let
  mister = "192.168.1.80";
in
{
  home.packages = lib.mkAfter [ pkgs.misterzine-jellyfin-update ];
  # Manual runs find the MiSTer the same way the timer does.
  home.sessionVariables.MISTERZINE_HOST = mister;

  systemd.user.services.misterzine-jellyfin-update = {
    Unit.Description = "Update MisterZine Jellyfin on the MiSTer";
    Service = {
      Type = "oneshot";
      Nice = 10;
      Environment = [ "MISTERZINE_HOST=${mister}" ];
      # --auto: no password prompts, and a MiSTer that is off, busy or already
      # current is not a failure. Nothing is installed while the app runs.
      ExecStart = "${lib.getExe pkgs.misterzine-jellyfin-update} --auto";
    };
  };

  systemd.user.timers.misterzine-jellyfin-update = {
    Unit.Description = "Check for new MisterZine Jellyfin releases";
    Timer = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
