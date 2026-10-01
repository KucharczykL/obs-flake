{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  makeWrapper ? pkgs.makeWrapper,
  perl ? pkgs.perl,
  ...
}:
stdenv.mkDerivation {
  pname = "obs-service-format_spec_file";
  version = "0-unstable-2026-03-20";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-service-format_spec_file";
    rev = "eea57bd978899bf99d6eea971e60688019b1b0b4";
    hash = "sha256-TdW8HhYxU5FIh76N8JVwcOaL70+TRNESon91wynX+dE=";
  };

  # prepare_spec is core-perl only; perl here lets patchShebangs rewrite it.
  nativeBuildInputs = [
    makeWrapper
    perl
  ];

  dontConfigure = true;
  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    make check
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    make install DESTDIR=$out prefix=
    svcdir=$out/lib/obs/service
    substituteInPlace "$svcdir/format_spec_file" \
      --replace-fail /usr/lib/obs/service/format_spec_file.files "$svcdir/format_spec_file.files"
    patchShebangs "$svcdir"
    # prepare_spec derives the copyright year from SOURCE_DATE_EPOCH, which
    # nix develop pins to 1980.
    wrapProgram "$svcdir/format_spec_file" --unset SOURCE_DATE_EPOCH
    runHook postInstall
  '';

  meta = {
    description = "OBS source service that normalizes spec files (format_spec_file)";
    homepage = "https://github.com/openSUSE/obs-service-format_spec_file";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
