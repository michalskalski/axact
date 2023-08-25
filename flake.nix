{
   inputs = {
       nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
       flake-utils.url = "github:numtide/flake-utils";
       rust-overlay = {
         url = "github:oxalica/rust-overlay";
         inputs = {
           nixpkgs.follows = "nixpkgs";
           flake-utils.follows = "flake-utils";
         };
       };
       crane = {
          url = "github:ipetkov/crane";
          inputs = {
            nixpkgs.follows = "nixpkgs";
            rust-overlay.follows = "rust-overlay";
            flake-utils.follows = "flake-utils";
          };
        };

     };
     outputs = { nixpkgs, flake-utils, rust-overlay, crane, ... }:
         flake-utils.lib.eachDefaultSystem (system:
             let
                overlays = [ (import rust-overlay) ];
                pkgs = import nixpkgs { inherit system overlays; };
                rustToolchain = pkgs.rust-bin.stable.latest.default.override {
                    extensions = [ "rust-src" ];
                };

                craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
                includeAssets = path: _type: builtins.match ".*index\.(html|css|mjs)" path != null;
                cleanSource = path: type:
                  (includeAssets path type) || (craneLib.filterCargoSources path type);

                src = pkgs.lib.cleanSourceWith {
                  src = ./.;
                  filter = cleanSource;
                };
                #src = craneLib.cleanCargoSource ./.;


                darwinPkgs = pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
                   # https://github.com/GuillaumeGomez/sysinfo/issues/915
                   pkgs.darwin.apple_sdk_11_0.frameworks.CoreFoundation
                   CoreServices
                   IOKit
                   Security
                ]);

                nativeBuildInputs = with pkgs; [ rustToolchain pkg-config darwinPkgs ] ;
                buildInputs = with pkgs; [ openssl ];

                commonArgs = {
                  inherit src buildInputs nativeBuildInputs;
                };

                cargoArtifacts = craneLib.buildDepsOnly commonArgs;

                bin = craneLib.buildPackage (commonArgs // {
                  inherit cargoArtifacts;
                });

                ociImage = pkgs.dockerTools.buildImage {
                  name = "axact";
                  tag  = "latest";
                  copyToRoot = pkgs.buildEnv {
                    name = "image-root";
                    paths = [ bin ];
                    pathsToLink = [ "/bin" ];

                  };
                  config = {
                    Cmd = [ "${bin}/bin/axact" ];
                  };
                };

              in
              with pkgs;
              {
                packages = {
                 inherit bin ociImage;
                 default = bin;
                };

                devShell = mkShell {
                    #inherit buildInputs nativeBuildInputs;
                    inputsFrom = [ bin ];
                    buildInputs = [dive skopeo] ++ darwinPkgs;
                };
              });
}
