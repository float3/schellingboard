---
title: "NixOS"
description: "Run SchellingBoard as a NixOS service, from the published container."
type: guide
---

# NixOS

The flake in the repository has a NixOS module that runs the same container
[Deployment](deployment.md) describes, as a system service: started at boot,
restarted if it stops, logging to the journal, and with its data in one
directory you can back up.

It does not build the app from source. SchellingBoard is a Bun workspace with
two native addons and dependencies that are bumped every week, so a
source build in Nix would need a dependency hash that goes stale faster than
anyone would fix it. The module runs the published image instead, which means
a release is a tag and nothing else has to move.

## Add it to your system

```nix
{
  inputs.schellingboard.url = "github:schellingboard/schellingboard";

  outputs = { nixpkgs, schellingboard, ... }: {
    nixosConfigurations.venue = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        schellingboard.nixosModules.default
        {
          virtualisation.podman.enable = true;

          services.schellingboard = {
            enable = true;
            image = "schellingboard/schellingboard:4.0.0";
            environmentFile = "/run/secrets/schellingboard";
            settings.SITE_URL = "https://sessions.example.org";
          };
        }
      ];
    };
  };
}
```

`virtualisation.oci-containers.backend` decides whether that is Podman or
Docker; enable whichever you already run.

## Secrets

`settings` is for everything that is not secret: it ends up in the Nix store,
which every user on the machine can read. `SITE_PASSWORD`, `ADMIN_PASSWORD`,
`AUTH_SECRET`, `SMTP_PASSWORD` and `SMTP_URL` go in `environmentFile`
instead, a file of `NAME=value` lines placed by your secret manager or by
hand with mode `0400`:

```
SITE_PASSWORD=changeme
ADMIN_PASSWORD=changeme
AUTH_SECRET=a-long-random-string
```

Generate `AUTH_SECRET` with `openssl rand -base64 32`. The module refuses to
build if one of those three turns up in `settings`.

Every variable the app reads is in [Configuration](configuration.md).

## Serve it over HTTPS

The module publishes the app on `127.0.0.1:3000` by default, for a reverse
proxy in front of it. Adding the site to a phone's home screen, and the
notifications that come with it, only work on an `https://` address:

```nix
services.nginx = {
  enable = true;
  virtualHosts."sessions.example.org" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:3000";
  };
};
```

Set `services.schellingboard.openFirewall` instead if you want to reach the
app directly — a laptop on the venue's wifi for a trial run, where the
install-to-home-screen features are not wanted.

## Data and backups

Everything is under `services.schellingboard.dataDir`, by default
`/var/lib/schellingboard`: `data.db` and the uploaded files. Back that
directory up as [Backup and restore](backup.md) describes; the directory is
owned by uid 1001, the container's own user.

## A shell for working on it

The same flake has a development shell with Bun, Node and what the native
addons need to compile:

```bash
nix develop
make install
make dev
```
