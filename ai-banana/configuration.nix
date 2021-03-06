let
  webdavPort = 8080;
  calibreWebPort = 8083;
  kobodlPort = 8084;
  resilio = {
    listeningPort = 18776;
    dirs = {
      "music" = "readonly";
      "photo" = "readonly";
      "books" = "readwrite";
      "jasper" = "readonly";
      "hiske" = "readonly";
      "hjgames" = "readwrite";
    };
    pathFor = dir: "/srv/volume1/${dir}";
  };
in inputs:
{ pkgs, config, modulesPath, ... }: {

  # Nix
  system.stateVersion = "20.03";
  networking.hostName = "ai-banana";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ inputs.self.overlays.linuxCustomPkgs ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Hardware
  disabledModules = [ "services/networking/resilio.nix" ];
  imports = [
    ../shared/nixos-modules/resilio.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ];
  boot.loader.grub.device = "/dev/sda";
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };
  fileSystems."/srv/volume1" = {
    device = "/dev/disk/by-id/scsi-0HC_Volume_6344799";
    fsType = "ext4";
    options = [ "discard" "defaults" ];
  };

  # Enable IP forwarding to allow this machine to function as a tailscale exit
  # node.
  # See: https://tailscale.com/kb/1104/enable-ip-forwarding/
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

  # Packages
  environment.systemPackages = [ pkgs.tailscale ];

  # Tailscale
  services.tailscale.enable = true;

  # SSH
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = let
    sshKeysSrc = builtins.fetchurl {
      url = "https://github.com/jwoudenberg.keys";
      sha256 = "1770msnmbxhbsq8j6iznz816jbz7rm9ss45bjahlqsb3570hdvqf";
    };
  in builtins.filter (line: line != "")
  (pkgs.lib.splitString "\n" (builtins.readFile sshKeysSrc));

  # Mosh
  programs.mosh.enable = true;

  # Network
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts = [
      resilio.listeningPort
      2022 # ssh
    ];
    allowedUDPPorts = [
      resilio.listeningPort
      config.services.tailscale.port
      2022 # ssh
    ];
  };

  # healthchecks.io
  services.cron.enable = true;
  services.cron.systemCronJobs = [
    "0 * * * *      root    ls -1qA /srv/volume1/hjgames/scans-to-process/ | grep -q . || curl -fsS -m 10 --retry 5 -o /dev/null https://hc-ping.com/8ff8704b-d08e-47eb-b879-02ddb7442fe2"
  ];

  # Resilio Sync
  system.activationScripts.mkResilioSharedFolders = let
    pathList = pkgs.lib.concatMapStringsSep " " resilio.pathFor
      (builtins.attrNames resilio.dirs);
  in ''
    mkdir -p ${pathList}
    chown rslsync:rslsync -R ${pathList}
  '';

  services.resilio = {
    enable = true;
    enableWebUI = false;
    listeningPort = resilio.listeningPort;
    sharedFolders = let
      configFor = dir: perms: {
        secretFile = "/run/secrets/resilio_key_${dir}_${perms}";
        directory = resilio.pathFor dir;
        useRelayServer = false;
        useTracker = true;
        useDHT = true;
        searchLAN = true;
        useSyncTrash = false;
        knownHosts = [ ];
      };
    in builtins.attrValues (builtins.mapAttrs configFor resilio.dirs);
  };

  # Caddy
  services.caddy = {
    enable = true;
    email = "letsencrypt@jasperwoudenberg.com";
    # Hashes generated with the `caddy hash-password` command.
    config = ''
      :80 {
        respond / `
          <html>
            <head><title>ai-banana</title></head>
            <body>
              <h1>ai-banana</h1>
              <ul>
                <li><a href="/files/">files</a></li>
                <li><a href="/books/">books</a></li>
                <li><a href="http://ai-banana:${
                  toString (kobodlPort + 1)
                }">kobo upload</a></li>
                <li><a href="/upnp/">upnp</a></li>
              </ul>
            </body>
          </html>
        `

        redir /files /files/
        handle_path /files/* {
          reverse_proxy localhost:${toString webdavPort}
        }

        redir /upnp /upnp/
        handle_path /upnp/* {
          reverse_proxy localhost:58050
        }

        redir /books /books/
        reverse_proxy /books/* {
          to localhost:${toString calibreWebPort}
          header_up Authorization admin
          header_up X-Script-Name /books
        }
      }

      :${toString (kobodlPort + 1)} {
        reverse_proxy localhost:${toString kobodlPort}
      }
    '';
  };

  # calibre-web
  services.calibre-web = {
    enable = true;
    listen.port = calibreWebPort;
    user = "rslsync";
    group = "rslsync";
    options.calibreLibrary = "/srv/volume1/books";
    options.enableBookUploading = true;
    # Documentation on this reverse proxy setup:
    # https://github.com/janeczku/calibre-web/wiki/Setup-Reverse-Proxy
    options.reverseProxyAuth.enable = true;
    options.reverseProxyAuth.header = "Authorization";
  };

  # rclone
  systemd.services.rclone-serve-webdav = {
    description = "Rclone Serve";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "rslsync";
      Group = "rslsync";
      ExecStart =
        "${pkgs.rclone}/bin/rclone serve webdav /srv/volume1 --addr :${
          toString webdavPort
        }";
      Restart = "on-failure";
    };
  };

  systemd.services.rclone-serve-sftp = {
    description = "Rclone Serve";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "rslsync";
      Group = "rslsync";
      ExecStart = let
        script = pkgs.writeShellScriptBin "rclone-serve-sftp" ''
          #!/usr/bin/env bash
          exec ${pkgs.rclone}/bin/rclone serve sftp \
            /srv/volume1/hjgames/scans-to-process \
            --key /run/secrets/ssh-key \
            --user sftp \
            --pass "$RCLONE_PASS" \
            --addr :2022
        '';
      in "${script}/bin/rclone-serve-sftp";
      Restart = "on-failure";
      EnvironmentFile = "/run/secrets/sftp-password";
    };
  };

  # restic
  services.restic.backups.daily = {
    paths = builtins.map resilio.pathFor (builtins.attrNames resilio.dirs);
    repository = "sftp:19438@ch-s012.rsync.net:restic-backups";
    passwordFile = "/run/secrets/restic-password";
    timerConfig = { OnCalendar = "00:05"; };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
      "--keep-yearly 75"
    ];
  };

  systemd.services.restic-backups-daily.serviceConfig.ExecStartPre =
    "${pkgs.curl}/bin/curl -m 10 --retry 5 https://hc-ping.com/528b3b90-9fc4-4dd7-b032-abb0c7019b88/start";
  systemd.services.restic-backups-daily.serviceConfig.ExecStartPost =
    "${pkgs.curl}/bin/curl -m 10 --retry 5 https://hc-ping.com/528b3b90-9fc4-4dd7-b032-abb0c7019b88";

  # ocrmypdf
  systemd.paths.ocrmypdf = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
    description =
      "Triggers ocrmypdf service when a file is placed in the scans-to-process directory.";
    pathConfig = {
      DirectoryNotEmpty = "/srv/volume1/hjgames/scans-to-process";
      MakeDirectory = true;
    };
  };

  systemd.services.ocrmypdf = {
    enable = true;
    description =
      "Run ocrmypdf on all files in the scans-to-process directory.";
    serviceConfig = {
      Type = "oneshot";
      User = "rslsync";
      Group = "rslsync";
      ExecStart = let
        script = pkgs.writeShellScriptBin "ocr-scans-to-process" ''
          #!/usr/bin/env bash
          for file in /srv/volume1/hjgames/scans-to-process/*; do
            # Notify healthchecks.io that we're about to start scanning.
            ${pkgs.curl}/bin/curl --retry 3 https://hc-ping.com/8ff8704b-d08e-47eb-b879-02ddb7442fe2/start

            # Run ocrmypdf on the scanned file.
            output="$(mktemp -u "/tmp/$(date '+%Y%m%d')_XXXXXX.pdf")"
            ${pkgs.ocrmypdf}/bin/ocrmypdf \
              --output-type pdf \
              --rotate-pages \
              --skip-text \
              --language nld+eng \
              "$file" \
              "$output" \
              && rm "$file" \
              && mv "$output" /srv/volume1/hjgames/documenten

            # Notify healthchecks.io of the status of the previous command.
            ${pkgs.curl}/bin/curl --retry 3 https://hc-ping.com/8ff8704b-d08e-47eb-b879-02ddb7442fe2/$?
          done
        '';
      in "${script}/bin/ocr-scans-to-process";
    };
  };

  virtualisation.oci-containers = {
    containers.minimserver = {
      image = "minimworld/minimserver:2.0.16";
      autoStart = true;
      volumes = [
        "/srv/volume1/music:/Music"
        "/srv/volume1/minimserver-data:/opt/minimserver/data"
      ];
      environment = { TZ = "Europe/Amsterdam"; };
      extraOptions = [ "--network=host" ];
    };
    containers.bubbleupnpserver = {
      image = "bubblesoftapps/bubbleupnpserver";
      autoStart = true;
      extraOptions = [ "--network=host" ];
    };
    containers.kobodl =
      # configDir = pkgs.writeTextDir "config/kobodl.json" ''
      #   {
      #     "users": [];
      #     "calibre_web": {
      #       "enabled" = true,
      #       "url" = "localhost/books/upload",
      #       "username" = "",
      #       "password" = ""
      #     }
      #   }
      # '';
      {
        image = "subdavis/kobodl";
        autoStart = true;
        extraOptions = [ "--network=host" ];
        ports = [ "${toString kobodlPort}:${toString kobodlPort}" ];
        volumes = [ "/srv/volume1/kobodl:/kobodl" ];
        cmd = [
          "--config"
          "/kobodl/kobodl.json"
          "serve"
          "--host"
          "0.0.0.0"
          "--port"
          "${toString kobodlPort}"
        ];
      };
  };
}
