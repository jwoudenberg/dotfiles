# Temporary overlay to provide tabnine until the nixpkgs stable bundles it
# (looks like this will be in 21.05). This overlay is a lightly modified copy
# of the derivation currently present in nixpkgs-unstable:
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/tools/tabnine/default.nix#L39

self: super:

let
  version = "3.3.108";
  src = if super.stdenv.hostPlatform.system == "x86_64-darwin" then
    super.fetchurl {
      url =
        "https://update.tabnine.com/bundles/${version}/x86_64-apple-darwin/TabNine.zip";
      sha256 = "0b5la0mfar0d876zfs876mk3cw2g5cb4bhfqrx6midw7p3q80yib";
    }
  else if super.stdenv.hostPlatform.system == "x86_64-linux" then
    super.fetchurl {
      url =
        "https://update.tabnine.com/bundles/${version}/x86_64-unknown-linux-musl/TabNine.zip";
      sha256 = "vbeuZf/phOj83xTha+AzpKIvvrjwMar7q2teAmr5ESQ=";
    }
  else
    throw "Not supported on ${super.stdenv.hostPlatform.system}";
in {
  tabnine = super.stdenv.mkDerivation rec {
    pname = "tabnine";

    inherit version src;

    dontBuild = true;

    # Work around the "unpacker appears to have produced no directories"
    # case that happens when the archive doesn't have a subdirectory.
    setSourceRoot = "sourceRoot=`pwd`";

    nativeBuildInputs = [ super.unzip ];

    installPhase = ''
      install -Dm755 -t $out/bin TabNine TabNine-deep-cloud TabNine-deep-local WD-TabNine
    '';

    meta = with super.lib; {
      homepage = "https://tabnine.com";
      description =
        "Smart Compose for code that uses deep learning to help you write code faster";
      license = licenses.unfree;
      platforms = [ "x86_64-darwin" "x86_64-linux" ];
    };
  };
}