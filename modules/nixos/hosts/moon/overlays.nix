{inputs, ...}: {
  flake.nixosModules.moonOverlays = {
    pkgs,
    lib,
    ...
  }: {
    nixpkgs.overlays = let
      # ffmpeg built from plain nixpkgs, without moon's Pi overlays applied
      # (nixos-raspberrypi's own, and the ones below), so it stays the exact
      # derivation cache.nixos.org has.
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
        # Runtime fixes for 16 KiB pages.
        # See https://github.com/nvmd/nixos-raspberrypi/issues/64
        #
        # Keep this list to packages that are broken at RUNTIME when taken
        # from cache.nixos.org. Every override here changes a hash, and
        # everything depending on it then misses the cache and gets built on
        # vivivi, with moon holding the whole build closure. Overrides that
        # only skipped flaky build-time tests (gnutls, arrow-cpp, astropy,
        # websockets) were removed for that reason: gnutls alone sits under
        # glib and forced hundreds of rebuilds. Unmodified, those packages
        # come from the cache and their tests never run. If one ever has to
        # be built again and flakes, override just that one.
        #
        # Checked when this was pruned: of the 41 Rust packages in moon's
        # closure, only polars and uv-build vendor tikv-jemalloc-sys, and
        # uv-build is only a build input of a package that is itself
        # fetched, so it never runs. vectorchord (immich's pg extension)
        # uses mimalloc, which reads the page size at runtime.
        (final: prev: {
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
              })
            ];
        })
      ];
  };
}
