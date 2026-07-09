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
  pythonEnv = python3.withPackages (
    ps: with ps; [
      lxml
      python-dateutil
      pyyaml
    ]
  );
  # SCM handlers and archivers shell out to these via PATH.
  runtimeDeps = with pkgs; [
    git
    gnutar
    cpio
    gzip
    bzip2
    xz
    zstd
    coreutils
  ];
in
stdenv.mkDerivation rec {
  pname = "obs-service-tar_scm";
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-service-tar_scm";
    rev = "454b4bb864cbf75df2fedc1295d345a95b5cf3d0"; # tag 0.13.0
    hash = "sha256-f4lIuQ9C8+PYYESuZ7FJQgA14rAcPiEZphiZNtcwmes=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  # The service entry (tar_scm.py) appends its own dir to sys.path to find the
  # TarSCM module, so both live together in libexec. osc invokes the services
  # by basename (tar_scm/obs_scm/tar/...) and TarSCM picks its mode from
  # argv[0], so each name is a thin wrapper that preserves argv0 and injects
  # the runtime tools on PATH.
  installPhase = ''
    runHook preInstall

    libexec=$out/libexec/obs-service-tar_scm
    svcdir=$out/lib/obs/service
    mkdir -p "$libexec" "$svcdir"

    cp -r TarSCM "$libexec/"
    install -Dm755 tar_scm.py "$libexec/tar_scm"
    substituteInPlace "$libexec/tar_scm" \
      --replace-fail '#!/usr/bin/env python' '#!${pythonEnv}/bin/python3'

    install -Dm644 tar.service       "$svcdir/tar.service"
    install -Dm644 snapcraft.service "$svcdir/snapcraft.service"
    install -Dm644 appimage.service  "$svcdir/appimage.service"
    sed -e '/^===OBS_ONLY/,/^===/d' -e '/^===GBP_ONLY/,/^===/d' -e '/^===/d' \
      tar_scm.service.in > "$svcdir/tar_scm.service"
    sed -e '/^===TAR_ONLY/,/^===/d' -e '/^===GBP_ONLY/,/^===/d' -e '/^===/d' \
      tar_scm.service.in > "$svcdir/obs_scm.service"

    for name in tar_scm obs_scm tar appimage snapcraft; do
      makeWrapper "$libexec/tar_scm" "$svcdir/$name" \
        --argv0 "$name" \
        --prefix PATH : ${lib.makeBinPath runtimeDeps}
    done

    runHook postInstall
  '';

  passthru.serviceDir = "${placeholder "out"}/lib/obs/service";

  meta = {
    description = "OBS source service to prepare sources from SCM (tar_scm/obs_scm)";
    homepage = "https://github.com/openSUSE/obs-service-tar_scm";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "tar_scm";
  };
}
