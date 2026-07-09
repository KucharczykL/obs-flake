{ config, lib, ... }:
let
  cfg = config.programs.osc;
in
{
  options.programs.osc = {
    enable = lib.mkEnableOption "osc (Open Build Service client) oscrc configuration";

    apiurl = lib.mkOption {
      type = lib.types.str;
      default = "api.suse.de";
      description = "Default OBS/IBS API host (no scheme).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "OBS/IBS account name.";
    };

    sshkey = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path to the ssh private key used for authentication.";
    };

    buildType = lib.mkOption {
      type = lib.types.str;
      default = "podman";
      description = "vm-type for local `osc build` (podman/chroot/kvm/...).";
    };

    trustedProjects = lib.mkOption {
      type = lib.types.str;
      default = "SUSE:* openSUSE:*";
      description = ''
        Space-separated glob patterns of trusted build projects. Set up front
        so `osc build` does not prompt and try to persist them back to the
        (read-only) oscrc.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # osc credentials use TransientCredentialsManager (prompted) + ssh key, so
    # no secret lives in this file.
    xdg.configFile."osc/oscrc".text = lib.generators.toINI { } {
      general = {
        apiurl = cfg.apiurl;
        build-type = cfg.buildType;
      };
      "https://${cfg.apiurl}" = {
        user = cfg.user;
        credentials_mgr_class = "osc.credentials.TransientCredentialsManager";
        sshkey = cfg.sshkey;
        trusted_prj = cfg.trustedProjects;
      };
    };
  };
}
