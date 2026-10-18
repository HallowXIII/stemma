{
  description = "stemma: computed etymological lexicons for conlang families";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      haskellOverrides = pkgs: final: prev:
        let hlib = pkgs.haskell.lib.compose; in
        {
          # brassica 1.0.0 is marked broken in nixpkgs only because its
          # upper bounds are stale; the library builds fine without them.
          # Its test suite pulls in pandoc, so skip it.
          brassica = hlib.markUnbroken
            (hlib.doJailbreak (hlib.dontCheck prev.brassica));
          stemma = final.callCabal2nix "stemma" ./. { };
        };

      # Only the executable, without the library and GHC in its closure.
      stemmaFor = pkgs:
        pkgs.haskell.lib.compose.justStaticExecutables
          (pkgs.haskellPackages.override {
            overrides = haskellOverrides pkgs;
          }).stemma;
    in
    {
      # For a NixOS / home-manager config:
      #   nixpkgs.overlays = [ inputs.stemma.overlays.default ];
      #   environment.systemPackages = [ pkgs.stemma ];
      overlays.default = final: prev: { stemma = stemmaFor final; };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        haskellPackages = pkgs.haskellPackages.override {
          overrides = haskellOverrides pkgs;
        };
      in
      {
        packages.default = stemmaFor pkgs;
        packages.stemma = self.packages.${system}.default;

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };

        devShells.default = haskellPackages.shellFor {
          packages = p: [ p.stemma ];
          nativeBuildInputs = [
            haskellPackages.cabal-install
            haskellPackages.haskell-language-server
          ];
        };
      });
}
