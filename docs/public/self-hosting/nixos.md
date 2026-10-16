---
title: "NixOS"
description: "Run SchellingBoard as a NixOS service, from the published container."
type: guide
---

# NixOS

The flake in the repository has a NixOS module that runs the same container
[Deployment](deployment.md) describes, as a system service: started at boot, restarted if it stops,
logging to the journal, and with its data in one directory you can back up.

It does not build the app from source. SchellingBoard is a Bun workspace with two native addons and
dependencies that are bumped every week, so a source build in Nix would need a dependency hash that
goes stale faster than anyone would fix it. The module runs the published image instead, which means
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
            image = "docker.io/schellingboard/schellingboard:5.0.0";
            environmentFile = "/run/secrets/schellingboard";
            settings.SITE_URL = "https://sessions.example.org";
          };
        }
      ];
    };
  };
}
```

`virtualisation.oci-containers.backend` decides whether that is Podman or Docker; enable whichever
you already run. Keep the `docker.io/` in `image`: Podman refuses a short name when there is no
terminal to ask which registry is meant.

## Secrets

`settings` is for everything that is not secret: it ends up in the Nix store, which every user on
the machine can read. `AUTH_SECRET`, `SITE_PASSWORD`, `SMTP_PASSWORD` and `SMTP_URL` go in
`environmentFile` instead, a file of `NAME=value` lines placed by your secret manager or by hand
with mode `0400`:

```
AUTH_SECRET=a-long-random-string
SITE_PASSWORD=changeme
```

Generate `AUTH_SECRET` with `openssl rand -base64 32`. The module refuses to build if `AUTH_SECRET`,
`SITE_PASSWORD` or `SMTP_PASSWORD` turns up in `settings`.

Every variable the app reads is in [Configuration](configuration.md).

## The first site admin

On its first start the app logs a one-time link that makes whoever opens it a site admin. Find it in
the journal:

```bash
journalctl -u podman-schellingboard | grep -i admin
```

The unit is `docker-schellingboard` if Docker is your backend.

## Serve it over HTTPS

The module publishes the app on `127.0.0.1:3000` by default, for a reverse proxy in front of it.
Adding the site to a phone's home screen, and the notifications that come with it, only work on an
`https://` address:

```nix
services.nginx = {
  enable = true;
  # Passes X-Forwarded-For and X-Forwarded-Proto, which the app needs.
  recommendedProxySettings = true;
  virtualHosts."sessions.example.org" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:3000";
  };
};
```

On a loopback address the module sets `SB_TRUSTED_PROXIES=1`, so that the app sees each visitor's
own address behind that one proxy and failed logins are limited per visitor. Behind more than one
proxy, or with `address` set to something else, set `settings.SB_TRUSTED_PROXIES` yourself; see
[Behind a reverse proxy](configuration.md#behind-a-reverse-proxy).

Set `services.schellingboard.openFirewall` instead if you want to reach the app directly — a laptop
on the venue's wifi for a trial run, where the install-to-home-screen features are not wanted.

## Data and backups

Everything is under `services.schellingboard.dataDir`, by default `/var/lib/schellingboard`:
`data.db` and the uploaded files. Back that directory up as [Backup and restore](backup.md)
describes; the directory is owned by uid 1001, the container's own user.

## A shell for working on it

The same flake has a development shell with Bun, Node and what the native addons need to compile:

```bash
nix develop
make install
make dev
```
