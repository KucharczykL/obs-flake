{
  pkgs ? import <nixpkgs> { },
  symlinkJoin ? pkgs.symlinkJoin,
  callPackage ? pkgs.callPackage,
  ...
}:
# osc looks for source services in a single directory. Merge the individual
# service packages so tar_scm/obs_scm, recompress, ... all live side by side
# under <out>/lib/obs/service, which osc-obs then points osc at.
symlinkJoin {
  name = "obs-services";
  paths = [
    (callPackage ../obs-service-tar_scm { })
    (callPackage ../obs-service-recompress { })
    (callPackage ../obs-service-set_version { })
    (callPackage ../obs-service-source_validator { })
  ];
}
