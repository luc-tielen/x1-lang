{ compiler ? "ghc881", pkgs ? import ./nix/packages.nix {} }:

with pkgs;

let
  inherit (haskell.lib) doJailbreak dontCheck appendPatch;
  haskellPackages = haskell.packages.${compiler};
  hpack = haskellPackages.callPackage ./nix/hpack.nix {};
  haskellPkgs = haskellPackages.override {
    overrides = self: super: {
      hpack = self.callCabal2nix "hpack" hpack {};
      prettyprinter = self.prettyprinter_1_3_0;
      protolude = doJailbreak super.protolude;
      neat-interpolation = dontCheck super.neat-interpolation;
      hedgehog = self.callPackage ./nix/hedgehog.nix {};
    };
  };
  # We have to call hpack now ourselves since current hpack is broken
  hpack2cabal = name: src: pkgs.runCommand "hpack2cabal-${name}" {} ''
    ${hpack}/bin/hpack '${src}' - > "$out"
  '';
  source = nix-gitignore.gitignoreSource [] ./.;
  processedSource = hpack2cabal "besra" source;
  drv = haskellPkgs.callCabal2nix "besra" processedSource {};
in
  {
    besra = drv;
    besra-shell = haskellPkgs.shellFor {
      packages = p: [ drv ];
      buildInputs = with haskellPkgs; [
        cabal-install
        hpack
        hlint
        ghcid
      ];
      withHoogle = true;
    };
  }
