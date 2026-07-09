{
  description = "SUSE OBS/IBS release-notes packaging: osc, source services, local podman build, and the uprn workflow";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      pkgNames = [
        "osc-obs"
        "obs-services"
        "obs-service-tar_scm"
        "obs-service-recompress"
        "obs-service-set_version"
        "obs-service-source_validator"
        "obs-build"
        "obs-build-vc"
        "obs-build-perl"
        "susedoc-up"
      ];
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        obsPkgs = nixpkgs.lib.genAttrs pkgNames (n: pkgs.callPackage (./packages + "/${n}") { });
      in
      {
        packages = obsPkgs;

        # Generic devshell (no personal config). Consumers can build their own
        # with susedoc-up.override to inject news_ssh_key etc.
        devShells.obs = pkgs.mkShell {
          packages = [
            obsPkgs.osc-obs
            obsPkgs.obs-build
            obsPkgs.susedoc-up
          ];
          shellHook = ''
            echo "OBS devshell ready: osc, upchangelog, upnews, uprn, build"
          '';
        };
        devShells.default = self.devShells.${system}.obs;
      }
    )
    // {
      # Parameterized oscrc config: `imports = [ obs-flake.homeManagerModules.osc ]`
      # then set `programs.osc = { enable = true; user = ...; sshkey = ...; };`
      homeManagerModules.osc = import ./modules/osc.nix;
      homeManagerModules.default = self.homeManagerModules.osc;
    };
}
