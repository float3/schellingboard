# A NixOS service that runs the published SchellingBoard container.
#
# The app is built with Bun workspaces and two native addons (better-sqlite3
# against Node's ABI, sharp against libvips), and its dependencies are bumped
# by Dependabot. Packaging that from source in Nix means a fixed-output
# derivation whose hash changes with every bump, which would break this file
# more often than anyone would fix it. Running the image the project already
# publishes keeps the two in step for free: a release is a tag, and `image`
# below is the only thing that has to move.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.schellingboard;

  # The container's own user, from the Dockerfile. The data directory is bind
  # mounted into it, so it has to be owned by that uid on the host too.
  uid = 1001;
  gid = 1001;
in {
  options.services.schellingboard = {
    enable = lib.mkEnableOption "SchellingBoard, a scheduling app for participant-driven events";

    image = lib.mkOption {
      type = lib.types.str;
      default = "schellingboard/schellingboard:latest";
      example = "schellingboard/schellingboard:4.0.0";
      description = ''
        The container image to run. Pin a release tag rather than `latest` if
        you would like to choose when the app changes under your attendees.
      '';
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        The host address to publish the app on. The default keeps it off the
        network, for a reverse proxy to terminate TLS in front of: adding the
        site to a phone's home screen and notifications both need HTTPS.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "The host port to publish the app on.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/schellingboard";
      description = ''
        Where the SQLite database and uploaded files are kept. This is the
        directory to back up; see the Backup and restore guide.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/schellingboard";
      description = ''
        A file of `NAME=value` lines read into the container's environment,
        for the settings that are secret: `SITE_PASSWORD`, `ADMIN_PASSWORD`,
        `AUTH_SECRET`, `SMTP_PASSWORD` and `SMTP_URL`. Keep it out of the Nix
        store, which is world readable — write it with your secret manager, or
        place it by hand with mode 0400.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = lib.literalExpression ''
        {
          SITE_URL = "https://sessions.example.org";
          SMTP_FROM = "sessions@example.org";
          SMTP_HOST = "smtp.example.org";
          SMTP_PORT = "587";
        }
      '';
      description = ''
        Environment variables for everything that is not secret. Every name
        the app reads is listed in the Configuration guide. These end up in
        the Nix store, so put passwords in `environmentFile` instead.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open `port` in the firewall. Leave this off when a reverse proxy on
        the same host is what reaches the app.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !(cfg.settings ? SITE_PASSWORD || cfg.settings ? ADMIN_PASSWORD || cfg.settings ? AUTH_SECRET);
        message = ''
          services.schellingboard.settings holds SITE_PASSWORD, ADMIN_PASSWORD
          or AUTH_SECRET, which would be written to the world-readable Nix
          store. Put them in services.schellingboard.environmentFile.
        '';
      }
    ];

    virtualisation.oci-containers.containers.schellingboard = {
      inherit (cfg) image;
      autoStart = true;
      ports = ["${cfg.address}:${toString cfg.port}:3000"];
      volumes = ["${cfg.dataDir}:/data"];
      environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
      # DATABASE_URL and SB_UPLOADS_DIR are already set in the image, both
      # under /data; they are repeated here so that a reader of the
      # configuration can see what the volume above is for.
      environment =
        {
          DATABASE_URL = "file:/data/data.db";
          SB_UPLOADS_DIR = "/data/uploads";
        }
        // cfg.settings;
      log-driver = "journald";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${toString uid} ${toString gid} -"
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
