{ config, lib, ... }:
let
  cfg = config.programs.osc;
  blocks = [ cfg ] ++ lib.attrValues cfg.apis;
  hasPasswordFiles = lib.any (b: b.passwordFile != null) blocks;
  hasPasswords = lib.any (b: b.password != null) blocks;

  credentialsMgr =
    b:
    if b.password != null || b.passwordFile != null then
      "osc.credentials.PlaintextConfigFileCredentialsManager"
    else
      "osc.credentials.TransientCredentialsManager";

  # passwordFile values become placeholders, substituted at activation time.
  passAttrs =
    b:
    lib.optionalAttrs (b.password != null) { pass = b.password; }
    // lib.optionalAttrs (b.passwordFile != null) {
      pass = "PASSWORD_PLACEHOLDER:${b.passwordFile}";
    };

  apiBlock =
    b:
    {
      user = b.user;
      credentials_mgr_class = credentialsMgr b;
      sshkey = b.sshkey;
      trusted_prj = b.trustedProjects;
    }
    // passAttrs b;

  oscrcText = lib.generators.toINI { } (
    lib.recursiveUpdate
      {
        general = {
          apiurl = cfg.apiurl;
          build-type = cfg.buildType;
        };
      }
      (
        lib.recursiveUpdate { "https://${cfg.apiurl}" = apiBlock cfg; } (
          lib.mapAttrs' (name: value: lib.nameValuePair "https://${name}" (apiBlock value)) cfg.apis
        )
      )
  );

  passwordOptions = {
    password = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression "osConfig.sops.placeholder.obs_password";
      description = ''
        Password written verbatim into {option}`programs.osc.configText`.
        Pass a secret-manager placeholder and render the file outside the
        Nix store; see {option}`programs.osc.configFile`.
      '';
    };
    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path to a file containing the password. An activation
        script copies it into oscrc, so a changed password takes effect only
        when home-manager activation runs. Prefer `password` with
        {option}`programs.osc.configFile`.
      '';
    };
  };
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

    inherit (passwordOptions) password passwordFile;

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
      type = lib.types.attrsOf (
        lib.types.submodule {
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
            inherit (passwordOptions) password passwordFile;
            trustedProjects = lib.mkOption {
              type = lib.types.str;
              default = cfg.trustedProjects;
              defaultText = lib.literalExpression "config.programs.osc.trustedProjects";
              description = "Trusted build projects.";
            };
          };
        }
      );
      default = { };
      description = "Additional/configured OBS/IBS API endpoints.";
    };

    configText = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = oscrcText;
      defaultText = lib.literalMD "generated from the other `programs.osc` options";
      description = ''
        Generated oscrc contents, `password` values included. Feed this to a
        secret-manager template (e.g. `sops.templates.<name>.content`) and
        point {option}`programs.osc.configFile` at the rendered file.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression "osConfig.sops.templates.oscrc.path";
      description = ''
        Absolute path to an oscrc rendered outside the Nix store from
        {option}`programs.osc.configText`. `~/.config/osc/oscrc` becomes a
        symlink to it, so the secret manager keeps passwords current.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !lib.any (b: b.password != null && b.passwordFile != null) blocks;
            message = "programs.osc: set either password or passwordFile per API, not both.";
          }
          {
            assertion = hasPasswords -> cfg.configFile != null;
            message = "programs.osc: password is written into configText; render it outside the Nix store and set programs.osc.configFile.";
          }
          {
            assertion = cfg.configFile != null -> !hasPasswordFiles;
            message = "programs.osc: passwordFile is not substituted into configFile; use password.";
          }
        ];
      }

      (lib.mkIf (cfg.configFile != null) {
        xdg.configFile."osc/oscrc" = {
          source = config.lib.file.mkOutOfStoreSymlink cfg.configFile;
          # Replaces the regular file that writeOscrc left behind.
          force = true;
        };
      })

      (lib.mkIf (cfg.configFile == null && !hasPasswordFiles) {
        xdg.configFile."osc/oscrc".text = oscrcText;
      })

      (lib.mkIf (cfg.configFile == null && hasPasswordFiles) {
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
                echo "pass = $(cat "$pw_file")" >> "$TEMP_OSCRC"
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
    ]
  );
}
