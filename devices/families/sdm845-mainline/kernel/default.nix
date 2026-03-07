{
  mobile-nixos,
  fetchFromGitea,
  fetchpatch,
  stdenv,
  lib,
  bc,
  bison,
  flex,
  gcc,
  gnumake,
  perl,
  python3,
  zstd, # To compress kernel modules
  features ? [ ],
  ...
}@args:

let
  kernelSrc = fetchFromGitea {
    domain = "codeberg.org";
    owner = "sdm845";
    repo = "linux";
    rev = "dc7b19cffd9ef96b28da5441061ff26dce1025a6";
    hash = "sha256-5DJ/G7I193TVnVn08dA0UYtzSf6g/Us6/ep8DCaFAdQ=";
  };

  # Dynamically parse version from the Makefile

  kernelVersion = rec {
    file = "${kernelSrc}/Makefile";
    version = lib.head (builtins.match ".+VERSION = ([0-9]+).+" (builtins.readFile file));
    patchlevel = lib.head (builtins.match ".+PATCHLEVEL = ([0-9]+).+" (builtins.readFile file));
    sublevel = lib.head (builtins.match ".+SUBLEVEL = ([0-9]+).+" (builtins.readFile file));
    extraversion = lib.head (builtins.match ".+EXTRAVERSION = ([a-z0-9-]+).+" (builtins.readFile file));

# Trace statements to debug the parsed values
  _ = builtins.trace ("Parsed version: ${version}") null;
  _ = builtins.trace ("Parsed patchlevel: ${patchlevel}") null;
  _ = builtins.trace ("Parsed sublevel: ${sublevel}") null;
  _ = builtins.trace ("Parsed extraversion: ${extraversion}") null;

    string = "${version}.${patchlevel}.${sublevel}${
      lib.optionalString (extraversion != "") extraversion
    }";
  };

  # Target version string with suffix

  #targetVersion = "${kernelVersion.string}-sdm845";
  targetVersion = "${kernelVersion.string}";

  _ = builtins.trace ("Target version: ${targetVersion}") null;

  configfile = stdenv.mkDerivation {
    name = "sdm845-kernel-config";
    src = kernelSrc;

    nativeBuildInputs = [
      gnumake
      gcc
      bc
      bison
      flex
      perl
      python3
      zstd
    ];

    buildPhase = ''
  export ARCH=arm64
  export KCONFIG_CONFIG=$PWD/.config

  # Debugging output
  echo "Starting build with ARCH=${ARCH} and KCONFIG=${KCONFIG_CONFIG}"

  make defconfig
  echo "Defconfig created."

  # Merge sdm845.config fragment if it exists
  ./scripts/kconfig/merge_config.sh -m .config \
    arch/arm64/configs/sdm845.config \
    ${./defconfig}

  echo "Merged config."

  # Add essential NixOS required kernel options
  cat >>.config <${./defconfig}

  # Debugging output for the config file
  echo "Final config: $(cat .config)"

  make olddefconfig
  echo "Resolved dependencies."

  cp .config config
'';
  };
in

(mobile-nixos.kernel-builder {
  #version = "6.19.0-rc4-next-20260106-sdm845";
  version = targetVersion;
  modDirVersion = "${kernelVersion.string}";
_ = builtins.trace ("modDirVersion: ${modDirVersion}") null;
  #modDirVersion = targetVersion;
  configfile = configfile;
  src = kernelSrc;

  patches = [ ];

  nativeBuildInputs = [
    python3
    zstd
  ];

  makeFlags = [ "dtbs" ];

  # Don't use zinstall, it expects EFI boot files which ARM64 doesn't generate
  installTargets = [ ];

  isModular = true;
  isCompressed = "gz";

  postInstall = ''
    echo ":: Installing Image.gz kernel"
    cp -v "$buildRoot/arch/arm64/boot/Image.gz" "$out/Image.gz"
  '';

  # Match the EXTRAVERSION in Makefile to our target modDirVersion
  # Overwrite the DTB Makefile as requested
  postUnpack = ''
    cp ${./arch-arm64-boot-dts-sdm845-Makefile} $sourceRoot/arch/arm64/boot/dts/qcom/Makefile
  '';
  NIX_CFLAGS_COMPILE = "-Wno-error=return-type -Wno-error=implicit-function-declaration -Wno-error=int-conversion";
}
  #MOVED THIS GARBAGE OUT
  #substituteInPlace $sourceRoot/Makefile \
  #  --replace 'EXTRAVERSION = ${kernelVersion.extraversion}' 'EXTRAVERSION = ${kernelVersion.extraversion}-sdm845'
  # Add the compiler flags
).overrideAttrs
  (old: {
    NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "") + " " + (args.NIX_CFLAGS_COMPILE or "");
  })
