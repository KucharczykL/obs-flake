{
  pkgs ? import <nixpkgs> { },
  python3Packages ? pkgs.python3Packages,
  callPackage ? pkgs.callPackage,
  obs-services ? callPackage ../obs-services { },
  obs-build-vc ? callPackage ../obs-build-vc { },
  obs-build ? callPackage ../obs-build { },
  ...
}:
# osc hardcodes several OBS tool paths under /usr/lib/*, which do not exist on
# NixOS. Repoint them at the nix packages:
#   - source-service dir -> merged obs-services (obs_scm/tar_scm/recompress/...)
#   - vc_cmd fallback     -> obs-build-vc (changelog helper for `osc vc`)
#   - build/query* cmds   -> obs-build (local `osc build`)
python3Packages.osc.overrideAttrs (old: {
  # `osc build` verifies package signatures via the python rpm bindings, which
  # osc does not depend on by default.
  propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
    python3Packages.rpm
  ];

  postPatch = (old.postPatch or "") + ''
    substituteInPlace osc/obs_scm/serviceinfo.py \
      --replace-fail '/usr/lib/obs/service/' '${obs-services}/lib/obs/service/'
    substituteInPlace osc/conf.py \
      --replace-fail '"/usr/lib/build/vc"' '"${obs-build-vc}/bin/vc"' \
      --replace-fail '"/usr/bin/build"' '"${obs-build}/bin/build"' \
      --replace-fail '"/usr/lib/build/download_assets"' '"${obs-build}/lib/build/download_assets"' \
      --replace-fail '"/usr/lib/build/queryrecipe"' '"${obs-build}/lib/build/queryrecipe"' \
      --replace-fail '"/usr/lib/build/queryconfig"' '"${obs-build}/lib/build/queryconfig"'
  '';
})
