{
  description = "slides";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";

    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    flake-parts,
    nixpkgs,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.devenv.flakeModule];
      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = {pkgs, ...}: {
        devenv.shells.default = {
          dotenv.disableHint = true;

          languages.javascript = {
            enable = true;
            pnpm.enable = true;
            pnpm.install.enable = true;
          };

          env = let
            playwright-driver = pkgs.playwright-driver;
            playwright-driver-browsers = playwright-driver.browsers;
            playwright-browsers-json =
              builtins.fromJSON (builtins.readFile "${playwright-driver}/browsers.json");

            playwright-chromium =
              builtins.elemAt
              (builtins.filter (browser: browser.name == "chromium")
                playwright-browsers-json.browsers)
              0;
          in {
            PLAYWRIGHT_BROWSERS_PATH = "${playwright-driver-browsers}";
            PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = "${playwright-driver-browsers}/chromium-${playwright-chromium.revision}/chrome-linux/chrome";
            PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
            PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = 1;
          };
        };
      };
    };
}
