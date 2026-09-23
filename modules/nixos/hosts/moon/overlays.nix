{inputs, ...}: {
  flake.nixosModules.moonOverlays = {
    pkgs,
    lib,
    ...
  }: {
    nixpkgs.overlays = let
      # ffmpeg built from plain nixpkgs, without moon's Pi overlays applied
      # below (they patch things like arrow-cpp and gnutls that ffmpeg's
      # build closure doesn't touch, but importing nixpkgs fresh here keeps
      # this binding decoupled from whatever else this file overlays).
      upstreamPkgs = import inputs.nixpkgs {inherit (pkgs.stdenv.hostPlatform) system;};
      unstablePkgs = import inputs.nixpkgs-unstable {inherit (pkgs.stdenv.hostPlatform) system;};
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
          # mergerfs deliberately pulled from unstable (2.42.0 vs stable's
          # 2.41.1). This is a deliberate cross-channel pull and costs moon
          # a second stdenv/glibc chain in its closure -- keep it unless a
          # stable bump catches up.
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
          # gnutls: gnulib's `test-lock` hangs in test_recursive_lock and is
          # killed by its own alarm (exit 142) on the aarch64 builder. Stub
          # the test out rather than dropping doCheck, so the rest of gnutls'
          # suite (the crypto/TLS tests that actually matter) still runs.
          gnutls = prev.gnutls.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + ''
                echo 'int main (void) { return 0; }' > src/gl/tests/test-lock.c
              '';
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
                # websockets: tests.sync.test_connection's
                # test_writing_in_recv_events_fails races on a loaded builder
                # and dies with "no close frame received or sent". 2 errors out
                # of 1959 tests, both the same timing assumption. Pulled in by
                # immich-machine-learning via fastapi-cli, so a flake here
                # fails the whole moon closure. Its unittest runner has no
                # clean way to deselect two cases, hence the whole suite.
                websockets = pyPrev.websockets.overridePythonAttrs (_: {
                  doCheck = false;
                  dontCheck = true;
                });
              })
            ];
        })
      ];
  };
}
