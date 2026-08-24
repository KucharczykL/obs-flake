{ config, lib, ... }:
let
  cfg = config.programs.osc;
  hasPasswords = (cfg.passwordFile != null) || (lib.any (api: api.passwordFile != null) (lib.attrValues cfg.apis));

  # Generate the entire INI structure with placeholders for passwords so we don't
  # expose secrets in the Nix store.
  oscrcText = lib.generators.toINI { } (
    let
      defaultApiBlock = {
        "https://${cfg.apiurl}" = {
          user = cfg.user;
          credentials_mgr_class = if cfg.passwordFile != null then "osc.credentials.PlaintextConfigFileCredentialsManager" else "osc.credentials.TransientCredentialsManager";
          sshkey = cfg.sshkey;
          trusted_prj = cfg.trustedProjects;
        } // (lib.optionalAttrs (cfg.passwordFile != null) {
          pass = "PASSWORD_PLACEHOLDER:${cfg.passwordFile}";
        });
      };
      additionalApiBlocks = lib.mapAttrs' (name: value: lib.nameValuePair "https://${name}" ({
        user = value.user;
        credentials_mgr_class = if value.passwordFile != null then "osc.credentials.PlaintextConfigFileCredentialsManager" else "osc.credentials.TransientCredentialsManager";
        sshkey = value.sshkey;
        trusted_prj = value.trustedProjects;
      } // (lib.optionalAttrs (value.passwordFile != null) {
        pass = "PASSWORD_PLACEHOLDER:${value.passwordFile}";
      }))) cfg.apis;
    in
    lib.recursiveUpdate {
      general = {
        apiurl = cfg.apiurl;
        build-type = cfg.buildType;
      };
    } (lib.recursiveUpdate defaultApiBlock additionalApiBlocks)
  );
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

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Absolute path to a file containing the default API account password.";
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

    apis = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          user = lib.mkOption {
            type = lib.types.str;
            default = cfg.user;
            defaultText = lib.literalExpression "config.programs.osc.user";
            description = "OBS/IBS account name for this API.";
          };
          sshkey = lib.mkOption {
            type = lib.types.str;
            default = cfg.sshkey;
            defaultText = lib.literalExpression "config.programs.osc.sshkey";
            description = "Absolute path to the ssh private key.";
          };
          passwordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Absolute path to a file containing the account password for this API.";
          };
          trustedProjects = lib.mkOption {
            type = lib.types.str;
            default = cfg.trustedProjects;
            defaultText = lib.literalExpression "config.programs.osc.trustedProjects";
            description = "Trusted build projects.";
          };
        };
      });
      default = { };
      description = "Additional/configured OBS/IBS API endpoints.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (!hasPasswords) {
      xdg.configFile."osc/oscrc".text = oscrcText;
    })

    (lib.mkIf hasPasswords {
      home.activation.writeOscrc = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Ensure config directory exists
        run mkdir -p "$HOME/.config/osc"

        # Temporary file for building oscrc
        TEMP_OSCRC=$(mktemp)

        # Loop through the Nix-generated config structure and replace password
        # placeholders securely with their decrypted values at activation time.
        # Note: lib.generators.toINI quotes string values containing special
        # characters (like paths), so we strip optional quotes from the value.
        while IFS= read -r line; do
          if [[ "$line" =~ ^pass=\"?PASSWORD_PLACEHOLDER:([^\"]*)\"?$ ]]; then
            pw_file="''${BASH_REMATCH[1]}"
            if [ -f "$pw_file" ]; then
              echo "pass = \$(cat "$pw_file")" >> "$TEMP_OSCRC"
            fi
          else
            echo "$line" >> "$TEMP_OSCRC"
          fi
        done << 'EOF'
${oscrcText}
EOF

        # Move temp file to destination and set secure permissions
        run mv -f "$TEMP_OSCRC" "$HOME/.config/osc/oscrc"
        run chmod 600 "$HOME/.config/osc/oscrc"
      '';
    })
  ]);
}
