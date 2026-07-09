{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  makeWrapper ? pkgs.makeWrapper,
  ...
}:
let
  runtimeDeps = with pkgs; [
    gzip
    bzip2
    xz
    zstd
    gnutar
    coreutils
    which
  ];
in
stdenv.mkDerivation {
  pname = "obs-service-recompress";
  version = "0-unstable-2023-11-08";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-service-recompress";
    rev = "b1c7e9f161c1952bec0d7682c897123c56ea5827";
    hash = "sha256-RN94mBMgLFkBaL+XVQClztby2bWz2Ry4j+Zwwv5vrKI=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    svcdir=$out/lib/obs/service
    install -Dm644 recompress.service "$svcdir/recompress.service"
    install -Dm755 recompress "$svcdir/recompress"
    wrapProgram "$svcdir/recompress" \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
    runHook postInstall
  '';

  meta = {
    description = "OBS source service to recompress files (e.g. tar.gz)";
    homepage = "https://github.com/openSUSE/obs-service-recompress";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
