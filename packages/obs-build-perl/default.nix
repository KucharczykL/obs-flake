{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  ...
}:
# The Build / Build::Rpm perl modules out of obs-build. source_validator's
# spec checks (spec_query) use Build::Rpm::parse, which works standalone from
# PERL5LIB with no /usr/lib/build config files. Shipped as a plain module tree.
stdenv.mkDerivation {
  pname = "obs-build-perl";
  version = "0-unstable-2026";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-build";
    rev = "8a3b679b865f52c54e3f0572fedcaeb39a761584";
    hash = "sha256-f44PKhqGcXDeLvc8NzHGG+5mhCdEX6K0oI3Jn4uKhYM=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dst=$out/lib/perl5
    mkdir -p "$dst"
    cp Build.pm "$dst/"
    cp -r Build "$dst/"
    runHook postInstall
  '';

  passthru.perl5lib = "${placeholder "out"}/lib/perl5";

  meta = {
    description = "Build / Build::Rpm perl modules from obs-build";
    homepage = "https://github.com/openSUSE/obs-build";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
