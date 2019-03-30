{ compiler ? "ghc843", pkgs ? import ./packages.nix {} }:

with pkgs;

let
  haskellPkgs = haskell.packages.${compiler};
  drv = haskellPkgs.callCabal2nix "x1" ./. {};
in
  {
    x1 = drv;
    x1-shell = haskellPkgs.shellFor {
      packages = p: [ drv ];
      buildInputs = with haskellPkgs; [
        pkgs.git
        pkgs.less
        pkgs.gnupg
        cabal-install
        hlint
        #ghcid
        #neovim
      ];
      withHoogle = true;
    };
  }