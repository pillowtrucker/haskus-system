{pkgs, ...}: {
  # name = "project-name";
  compiler-nix-name = "ghc902"; # Version of GHC to use

  crossPlatforms = p: pkgs.lib.optionals pkgs.stdenv.hostPlatform.isx86_64 ([
#    p.mingwW64
    # p.ghcjs # TODO GHCJS support for GHC 9.2
  ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    p.musl64
  ]);

  # Tools to include in the development shell
  shell.tools.cabal = "latest";
#  shell.tools.hlint = "3.4";
#  shell.tools.haskell-language-server="latest";
  shell.tools.hlint = "3.3.6";
  shell.tools.haskell-language-server = "2.4.0.0";
}
