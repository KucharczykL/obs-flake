{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  fetchFromGitHub ? pkgs.fetchFromGitHub,
  makeWrapper ? pkgs.makeWrapper,
  gnumake ? pkgs.gnumake,
  perl ? pkgs.perl,
  ...
}:
let
  # perl with Date::Parse/Time::Zone; changelog2spec (and friends) need it to
  # turn .changes into the RPM %changelog. Used for patchShebangs so the perl
  # helpers resolve to an interpreter that actually has the modules.
  perlEnv = perl.withPackages (p: with p; [ TimeDate ]);
  # Host-side tools the `build` orchestrator shells out to when driving a
  # podman build root. Extended as the first real build surfaces gaps.
  runtimeDeps = with pkgs; [
    podman
    perlEnv
    rpm
    curl
    gnutar
    cpio
    zstd
    gzip
    xz
    bzip2
    coreutils
    gnused
    gnugrep
    gawk
    findutils
    util-linux
    file
    patch
    diffutils
  ];
in
stdenv.mkDerivation {
  pname = "obs-build";
  version = "0-unstable-2026";

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "obs-build";
    rev = "8a3b679b865f52c54e3f0572fedcaeb39a761584";
    hash = "sha256-f44PKhqGcXDeLvc8NzHGG+5mhCdEX6K0oI3Jn4uKhYM=";
  };

  nativeBuildInputs = [
    makeWrapper
    gnumake
    perlEnv
  ];

  dontConfigure = true;
  dontBuild = true;

  # Upstream Makefile installs everything (scripts + perl + configs) under
  # $out/lib/build with $out/bin/build symlinks; there is no compile step.
  installPhase = ''
    runHook preInstall
    make install prefix=$out
    patchShebangs $out/lib/build $out/bin

    # The perl helpers resolve @INC (Build.pm) and the config dir from
    # $BUILD_DIR, defaulting to the non-existent /usr/lib/build. osc invokes
    # these query tools directly with no env, so repoint their fallback at the
    # store path. (`build` instead exports BUILD_DIR to its children below.)
    for f in queryconfig queryrecipe download_assets; do
      substituteInPlace $out/lib/build/$f \
        --replace-quiet "'/usr/lib/build'" "'$out/lib/build'"
    done

    # build-vm copies BUILD_DIR (our read-only 0555 store) into the build root
    # with `cp -a`, then re-execs the 2nd-stage `/.build/build` inside the
    # container. Two NixOS fixups on that copy:
    #   1. restore owner write (else the 2nd-stage build.data write fails);
    #   2. rewrite our nix-store shebangs back to /usr/bin/* — inside the SUSE
    #      container the /nix/store interpreters do not exist, so exec fails
    #      with ENOENT. The preinstalled bash/perl provide /usr/bin/{bash,perl}.
    substituteInPlace $out/lib/build/build-vm \
      --replace-fail \
        'cp -a $BUILD_DIR/. $BUILD_ROOT/.build' \
        'cp -a $BUILD_DIR/. $BUILD_ROOT/.build && chmod -R u+w $BUILD_ROOT/.build && { grep -rlZ "^#!/nix/store" $BUILD_ROOT/.build 2>/dev/null | xargs -0 -r sed -i -E "1s|^#!/nix/store/[^ ]*/bin/([^ /]+)|#!/usr/bin/\1|"; }'

    # The podman createContainer hook runs unpackarchive on the HOST (to seed
    # the container rootfs), so it must use the host copy with our nix-store
    # shebang, not the container copy we rewrote to /usr/bin/perl above.
    substituteInPlace $out/lib/build/build-vm-podman \
      --replace-fail \
        'exec "$BUILD_ROOT/.build/unpackarchive"' \
        'exec "$BUILD_DIR/unpackarchive"'

    # build hardcodes BUILD_DIR=/usr/lib/build unless the env var is set.
    wrapProgram $out/bin/build \
      --set BUILD_DIR $out/lib/build \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
    runHook postInstall
  '';

  meta = {
    description = "OpenSUSE build script (obs-build) for local package builds";
    homepage = "https://github.com/openSUSE/obs-build";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "build";
  };
}
