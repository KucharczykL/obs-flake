{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  makeWrapper ? pkgs.makeWrapper,
  ...
}:
let
  # vc shells out to date/md5sum/stat/getent and dnsdomainname for the mail
  # domain. rpmdev-packager is optional (it falls back to getent passwd).
  runtimeDeps = with pkgs; [
    coreutils
    getent
    hostname # dnsdomainname
    gnused
    gawk
  ];
in
# Just the `vc` changelog helper out of obs-build; osc calls it for `osc vc`
# and changelog generation. The full build package is not needed here.
stdenv.mkDerivation {
  pname = "obs-build-vc";
  version = "0-unstable-2026";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-build";
    rev = "8a3b679b865f52c54e3f0572fedcaeb39a761584";
    hash = "sha256-f44PKhqGcXDeLvc8NzHGG+5mhCdEX6K0oI3Jn4uKhYM=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 vc "$out/bin/vc"
    wrapProgram "$out/bin/vc" \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
    runHook postInstall
  '';

  meta = {
    description = "vc changelog helper from obs-build (for osc vc)";
    homepage = "https://github.com/openSUSE/obs-build";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "vc";
  };
}
