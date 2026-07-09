{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  makeWrapper ? pkgs.makeWrapper,
  perl ? pkgs.perl,
  python3 ? pkgs.python3,
  callPackage ? pkgs.callPackage,
  obs-build-perl ? callPackage ../obs-build-perl { },
  ...
}:
let
  # Date::Parse / Time::Zone for the changelog date checks.
  perlEnv = perl.withPackages (p: with p; [ TimeDate ]);
  # Tools the individual checks shell out to.
  runtimeDeps = with pkgs; [
    perlEnv
    python3
    rpm
    gnupg # gpg, for keyring validation
    diffutils
    gnused
    gnugrep
    findutils
    libxml2 # xmllint
    coreutils
    gawk
  ];
in
stdenv.mkDerivation {
  pname = "obs-service-source_validator";
  version = "0-unstable-2024";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-service-source_validator";
    rev = "b2ab4c8f41cfeefbceae5886721140fc359ee9ce";
    hash = "sha256-SczQAo7ivJxHY6hB75plgU5NyygX08XBMphPt3cs6qI=";
  };

  # perlEnv/python3 must be in nativeBuildInputs so patchShebangs rewrites the
  # perl/python check scripts to interpreters that actually have their modules.
  nativeBuildInputs = [
    makeWrapper
    perlEnv
    python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    svcdir=$out/lib/obs/service
    vdir=$svcdir/source_validators
    mkdir -p "$vdir/helpers"

    install -Dm755 source_validator "$svcdir/source_validator"
    install -Dm644 source_validator.service "$svcdir/source_validator.service"
    install -m755 [0-9]* "$vdir/"
    install -m755 helpers/* "$vdir/helpers/"

    # The scripts hardcode the FHS service dir; point them at the store path.
    find "$svcdir" -type f -exec \
      sed -i "s|/usr/lib/obs/service/source_validators|$vdir|g" {} +

    patchShebangs "$svcdir"

    # osc invokes the top-level validator; the sub-checks/helpers it spawns
    # inherit PATH and PERL5LIB (Build::Rpm lives outside the interpreter env).
    wrapProgram "$svcdir/source_validator" \
      --prefix PATH : ${lib.makeBinPath runtimeDeps} \
      --prefix PERL5LIB : ${obs-build-perl}/lib/perl5

    runHook postInstall
  '';

  meta = {
    description = "OBS source service that validates package sources (source_validator)";
    homepage = "https://github.com/openSUSE/obs-service-source_validator";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
