{
  flake.homeModules.enchant = {pkgs, ...}: {
    # Pin which Enchant provider serves each language (used by jinx in
    # emacs); see the file's own commentary. The hunspell dictionaries it
    # pins to are installed here too -- Enchant finds them through the
    # per-user profile's share/hunspell on XDG_DATA_DIRS.
    xdg.configFile."enchant/enchant.ordering".source = ./enchant/enchant.ordering;

    home.packages = [
      pkgs.hunspellDicts.en_US
      pkgs.hunspellDicts.pt_PT
    ];
  };
}
