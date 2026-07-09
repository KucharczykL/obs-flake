{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  makeWrapper ? pkgs.makeWrapper,
  # osc patched to find the OBS source services (obs_scm/tar_scm).
  osc-obs ? pkgs.callPackage ../osc-obs { },
  # Declarative uprn config, written to $out/bin/uprn.conf (uprn sources it from
  # its own directory). Empty by default -- set keys where this is instantiated
  # (news_ssh_key, news_ssh_user, news_bug, osc_command, enabled_checks, ...).
  uprnSettings ? { },
  ...
}:
let
  uprnConf = pkgs.writeText "uprn.conf" (
    lib.concatMapStrings (s: s + "\n") (lib.mapAttrsToList (k: v: "${k}='${v}'") uprnSettings)
  );
  # Runtime tools the scripts shell out to.
  runtimeDeps = with pkgs; [
    osc-obs
    git
    libxml2 # xmllint
    coreutils
    gnused
    gnugrep
    util-linux # script (pty capture of `osc sr`)
  ];
in
stdenv.mkDerivation {
  pname = "susedoc-up";
  version = "0-unstable-2024-06-28";

  # Public mirror of gitlab.suse.de/susedoc/up (no VPN needed). Only the
  # scripts/ dir is checked out; the rest of the repo is large release-notes
  # content we do not need.
  src = fetchFromGitHub {
    owner = "SUSE";
    repo = "release-notes";
    rev = "ea932ed5037d788d3bd6b1c8d31be388dfa9f3cc";
    sparseCheckout = [ "scripts" ];
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    for script in upchangelog upnews uprn; do
      install -Dm755 "scripts/$script" "$out/bin/$script"
      wrapProgram "$out/bin/$script" \
        --prefix PATH : ${lib.makeBinPath runtimeDeps}
    done
    # uprn sources uprn.conf from its own dir ($out/bin after wrapping).
    install -Dm644 ${uprnConf} $out/bin/uprn.conf
    runHook postInstall
  '';

  meta = {
    description = "SUSE doc packaging helpers (upchangelog, upnews, uprn)";
    homepage = "https://github.com/SUSE/release-notes";
    platforms = lib.platforms.linux;
  };
}
