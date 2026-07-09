{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  makeWrapper ? pkgs.makeWrapper,
  python3 ? pkgs.python3,
  ...
}:
let
  pythonEnv = python3.withPackages (ps: with ps; [ packaging ]);
  runtimeDeps = with pkgs; [
    git
    coreutils
  ];
in
stdenv.mkDerivation {
  pname = "obs-service-set_version";
  version = "0-unstable-2024-01-11";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-service-set_version";
    rev = "7d8707d572dd2486b49054681e3250212f1eab0d";
    hash = "sha256-6kCiTjqWxILvH5kAWJ4P0Zguqd63UcGVNomWtOPirOw=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    svcdir=$out/lib/obs/service
    install -Dm644 set_version.service "$svcdir/set_version.service"
    install -Dm755 set_version "$svcdir/set_version"
    substituteInPlace "$svcdir/set_version" \
      --replace-fail '#!/usr/bin/python3' '#!${pythonEnv}/bin/python3'
    wrapProgram "$svcdir/set_version" \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
    runHook postInstall
  '';

  meta = {
    description = "OBS source service to update the version in spec/dsc files";
    homepage = "https://github.com/openSUSE/obs-service-set_version";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
