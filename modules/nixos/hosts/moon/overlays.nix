{inputs, ...}: {
  flake.nixosModules.moonOverlays = {
    pkgs,
    lib,
    ...
  }: {
    nixpkgs.overlays = let
      upstreamPkgs = import inputs.nixpkgs {system = pkgs.stdenv.hostPlatform.system;};
      unstablePkgs = import inputs.nixpkgs-unstable {system = pkgs.stdenv.hostPlatform.system;};
    in
      lib.mkAfter [
        (final: prev: {
          inherit
            (upstreamPkgs)
            ffmpeg
            ffmpeg-headless
            ffmpeg-full
            ffmpeg_7
            ffmpeg_7-headless
            ffmpeg_7-full
            ffmpeg_8
            ffmpeg_8-headless
            ffmpeg_8-full
            servarr-ffmpeg
            ;
          inherit (unstablePkgs) mergerfs;
        })
        # Workarounds for 16 KiB-page rpi5 builds.
        # See https://github.com/nvmd/nixos-raspberrypi/issues/64
        (final: prev: {
          # arrow-cpp: arrow-azurefs-test flakes against the Azurite Node.js
          # storage emulator on resource-constrained aarch64 builders. The
          # ctest run lives in installCheckPhase, not checkPhase, so both
          # doInstallCheck and dontInstallCheck have to be flipped.
          arrow-cpp = prev.arrow-cpp.overrideAttrs (_: {
            doCheck = false;
            doInstallCheck = false;
            dontCheck = true;
            dontInstallCheck = true;
          });
          pythonPackagesExtensions =
            prev.pythonPackagesExtensions
            ++ [
              (pyFinal: pyPrev: {
                # polars vendors `tikv-jemalloc-sys`, which bundles jemalloc
                # statically at build time. cache.nixos.org builds aarch64 on
                # 4 KiB-page hosts, so its cached polars aborts on moon with
                # "Unsupported system page size". Setting this env at build
                # time gives the override a unique hash (forcing a cache miss
                # so moon builds locally, where the bundled jemalloc auto-
                # detects 16 KiB pages and works at runtime).
                polars = pyPrev.polars.overridePythonAttrs (old: {
                  env = (old.env or {}) // {JEMALLOC_SYS_WITH_LG_PAGE = "14";};
                });
                # astropy: a handful of large-memory tests (test_read_big_table*,
                # test_heapsize_[PQ]_limit) are flaky on aarch64 / resource-
                # constrained builders.
                astropy = pyPrev.astropy.overridePythonAttrs (_: {
                  doCheck = false;
                  dontCheck = true;
                });
              })
            ];
        })
      ];
  };
}
