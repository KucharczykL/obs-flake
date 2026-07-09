# obs-flake

Nix packaging for the SUSE **OBS/IBS** release-notes workflow: `osc`, the OBS
source services, `obs-build` for local rootless-**podman** builds, and the
`susedoc-up` doc scripts — none of which need imperative setup.

## What's in it

**`devShells.obs`** (also `default`) — `osc`, `build`, and `upnews` / `uprn` /
`upchangelog` on `PATH`. `nix develop github:KucharczykL/obs-flake`.

**`packages.<system>`**
- `osc-obs` — `osc` with its hardcoded `/usr/lib/{obs/service,build}` paths
  repointed at the nix stores below, plus the python `rpm` bindings.
- `obs-services` — `tar_scm`/`obs_scm`, `recompress`, `set_version`,
  `source_validator` merged into one service dir (osc searches one dir).
- `obs-build` (+ `obs-build-vc`, `obs-build-perl`) — local `osc build`.
- `susedoc-up` — `upnews`/`uprn`/`upchangelog` from github `SUSE/release-notes`.
  Accepts a `uprnSettings` arg (attrset written to `uprn.conf`), empty by
  default.

**`homeManagerModules.osc`** — generates `~/.config/osc/oscrc`.

Local `osc build` needs rootless podman working on the host (subuid/subgid,
`newuidmap`; `virtualisation.podman.enable = true` on NixOS).

## Setup (flakes)

Add the input:

```nix
inputs.obs-flake = {
  url = "github:KucharczykL/obs-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### oscrc via home-manager

```nix
# home-manager config
imports = [ inputs.obs-flake.homeManagerModules.osc ];

programs.osc = {
  enable = true;
  user = "YOUR_OBS_LOGIN";
  sshkey = "/path/to/ssh/key";     # absolute path
  # apiurl = "api.suse.de";        # default
  # buildType = "podman";          # default
  # trustedProjects = "SUSE:* openSUSE:*";
};
```

(For home-manager inside a NixOS flake, pass `inputs` through with
`home-manager.extraSpecialArgs`.)

### devShell

Use it directly:

```
nix develop github:KucharczykL/obs-flake#obs
```

Or build your own with the `uprn` ssh key set (for the `uprn co` push):

```nix
devShells.obs = pkgs.mkShell {
  packages = [
    inputs'.obs-flake.packages.osc-obs
    inputs'.obs-flake.packages.obs-build
    (inputs'.obs-flake.packages.susedoc-up.override {
      uprnSettings.news_ssh_key = "/path/to/ssh/key";
    })
  ];
};
```
