{
  description = "stemma: computed etymological lexicons for conlang families";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        hlib = pkgs.haskell.lib.compose;

        haskellPackages = pkgs.haskellPackages.override {
          overrides = final: prev: {
            # brassica 1.0.0 is marked broken in nixpkgs only because its
            # upper bounds are stale; the library builds fine without them.
            # Its test suite pulls in pandoc, so skip it.
            brassica = hlib.markUnbroken
              (hlib.doJailbreak (hlib.dontCheck prev.brassica));
            stemma = final.callCabal2nix "stemma" ./. { };
          };
        };
      in
      {
        packages.default = haskellPackages.stemma;

        devShells.default = haskellPackages.shellFor {
          packages = p: [ p.stemma ];
          nativeBuildInputs = [
            haskellPackages.cabal-install
            haskellPackages.haskell-language-server
          ];
        };
      });
}
