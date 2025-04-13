{
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  json = pkgs.formats.json {};
  anubis = config.services.anubis;
  anubisInstance = lib.types.submoduleWith {
    modules = [
      anubis.instanceDefaults
      ({
        name,
        config,
        lib,
        ...
      }: let
        json = pkgs.formats.json {};
      in {
        options = with lib; {
          name = mkOption {
            type = types.str;
            description = "The name of this Anubis instance.";
            readOnly = true;
            default = name;
          };
          systemd = {
            socketActivated = mkEnableOption "socket activation";
            socketPath = mkOption {
              type = types.nullOr types.str;
              readOnly = true;
              default =
                if config.systemd.socketActivated
                then "/run/anubis/${name}/${name}.sock"
                else null;
            };
            metricsSocketPath = mkOption {
              type = types.nullOr types.str;
              readOnly = true;
              default =
                if config.systemd.socketActivated
                then "/run/anubis/${name}/metrics.sock"
                else null;
            };
          };
          target = mkOption {
            type = types.str;
            description = "The URL of the service that Anubis should forward valid requests to. Supports Unix domain sockets, set this to a URI like so: unix:///path/to/socket.sock.";
          };
          domain = mkOption {
            type = types.str;
            description = "The domain the Anubis challenge pass cookie should be set to. This should be set to the domain you bought from your registrar (EG: techaro.lol if your webapp is running on anubis.techaro.lol).";
          };
          env = mkOption {
            description = "Environment variables to set for this Anubis instance.";
            type = types.submoduleWith {
              modules = [
                ({lib, ...}: {
                  freeformType = with lib; types.attrsOf types.anything;
                  options = with lib; {
                    BIND = mkOption {
                      type = types.str;
                      description = "The network address that Anubis listens on. For unix, set this to a path: `/run/anubis/instance.sock`";
                    };
                    BIND_NETWORK = mkOption {
                      type = types.str;
                      description = "The address family that Anubis listens on. Accepts tcp, unix and anything Go's net.Listen supports.";
                      default = "tcp";
                    };
                    COOKIE_PARTITIONED = mkOption {
                      type = types.bool;
                      description = "If set to true, enables the partitioned (CHIPS) flag, meaning that Anubis inside an iframe has a different set of cookies than the domain hosting the iframe.";
                      default = false;
                    };
                    DIFFICULTY = mkOption {
                      type = types.ints.unsigned;
                      default = 5;
                    };
                    SOCKET_MODE = mkOption {
                      type = types.str;
                      default = "0770";
                    };
                    POLICY_FNAME = mkOption {
                      type = types.path;
                      default = anubis.defaultPolicyFile;
                    };
                  };
                })
              ];
            };
            default = {};
          };
          policy = mkOption {
            type = types.nullOr json.type;
            default = null;
          };
        };
        config = lib.mkMerge [
          {
            env = {
              TARGET = config.target;
              COOKIE_DOMAIN = config.domain;
            };
          }
          (lib.mkIf (config.policy != null) {
            env.POLICY_FNAME = json.generate "${config.name}.botPolicy.json" config.policy;
          })
          (lib.mkIf config.systemd.socketActivated {
            env = {
              BIND = config.systemd.socketPath;
              BIND_NETWORK = "unix";
              METRICS_BIND = config.systemd.metricsSocketPath;
              METRICS_BIND_NETWORK = "unix";
            };
          })
        ];
      })
    ];
  };
in {
  options = with lib; {
    services.anubis = {
      enable = (mkEnableOption "Anubis") // {default = anubis.instances != {};};
      package = mkPackageOption pkgs "anubis" {};
      defaultPolicy = mkOption {
        type = json.type;
        default = lib.importJSON "${anubis.package.src}/data/botPolicies.json";
      };
      defaultPolicyFile = mkOption {
        type = types.path;
        readOnly = true;
        default = json.generate "botPolicy.json" anubis.defaultPolicy;
      };
      instanceDefaults = mkOption {
        type = types.deferredModuleWith {
          staticModules = [];
        };
        description = "Default configuration merged into each instance.";
        default = {};
      };
      instances = mkOption {
        type = types.attrsOf anubisInstance;
        default = {};
      };
    };
    # services.nginx = {
    #   virtualHosts = mkOption {
    #     type = types.attrsOf (types.submoduleWith {
    #       shorthandOnlyDefinesConfig = true;
    #       modules = [
    #         ({
    #           name,
    #           config,
    #           lib,
    #           ...
    #         }: {
    #           options = with lib; {
    #             anubis = {
    #               enable = mkEnableOption "Anubis HTTP defense proxy";
    #             };
    #           };
    #           config =
    #             lib.mkIf config.anubis.enable {
    #             };
    #         })
    #       ];
    #     });
    #   };
    # };
  };
  disabledModules = [];
  imports = [];
  config = {
    # adapted from https://github.com/TecharoHQ/anubis/blob/878b37178d5b55046871ce53371eec5efb52cc78/run/anubis%40.service
    systemd.services = lib.mkMerge (map (inst: {
      "anubis@${inst.name}" = {
        description = "Anubis HTTP defense proxy (instance ${inst.name})";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${anubis.package}/bin/anubis";
          Restart = "always";
          RestartSec = "30s";
          EnvironmentFile = [(pkgs.writeText "${inst.name}.anubis.env" (lib.generators.toKeyValue {} inst.env))];
          LimitNOFILE = "infinity";
          DynamicUser = true;
          CacheDirectory = "anubis/${inst.name}";
          CacheDirectoryMode = "0755";
          StateDirectory = "anubis/${inst.name}";
          StateDirectoryMode = "0755";
          RuntimeDirectory = "anubis/${inst.name}";
          RuntimeDirectoryMode = "0755";
          ReadWritePaths = "/run";
        };
      };
    }) (attrValues anubis.instances));
  };
  meta = {};
}
