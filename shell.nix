with import <nixpkgs> { localSystem = "x86_64-darwin"; };

pkgs.mkShell rec {
  name = "qrGarminEnv";
  buildInputs = [
    pkgs.jdk
  ];

  packages = [
    pkgs.jq
    pkgs.python38Packages.python
    pkgs.python38Packages.pyqrcode
  ];

  # set java path for vscode monkeyC extension
  shellHook = ''
    settings=".vscode/settings.json"
    mkdir -p .vscode; test -f $settings || echo '{}' > $settings;
    jsonStr=$(cat $settings); jq '."monkeyC.javaPath" = "${pkgs.jdk}"' <<< "$jsonStr" > $settings;
    unset settings
  '';
}
