{
  description = "modus viewer: see and drive the screen of a distant machine, under a key that its owner allows.";

  inputs = {
    self.submodules = true;
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605";
    git-hooks = {
      url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The source of the system: the contract of the remote display, QUIC and TLS, the cryptography module. The viewer
    # compiles them from here (src/md/infrastructure/modus_source.md). modus publishes no FlakeHub release, and the
    # viewer needs its source only, not its flake.
    modus = {
      url = "github:sachahjkl/modus";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    git-hooks,
    modus,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib;

    wgpu = pkgs.fetchurl {
      url = "https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-linux-x86_64-release.zip";
      sha256 = "95a4d90c071005a98d03eab348beaa6b07e16eb00d1dcdb9f8348f75eb97ec5a";
    };

    # The compiler of gui_toolkit (odin.version), with wgpu-native where vendor:wgpu looks for it.
    odin = pkgs.stdenv.mkDerivation {
      pname = "odin";
      version = "dev-2026-11a";
      src = pkgs.fetchurl {
        url = "https://github.com/odin-lang/Odin/releases/download/dev-2026-11a/odin-linux-amd64-dev-2026-11a.tar.gz";
        sha256 = "65c9f6e97d6f8a30930e151f270ce5aeaa98fe8b2ba49fe067394e2af04f7618";
      };
      nativeBuildInputs = [pkgs.makeWrapper pkgs.unzip];
      dontBuild = true;
      dontPatchELF = true;
      installPhase = ''
        mkdir -p $out/lib/odin $out/bin
        cp -r . $out/lib/odin
        dest=$out/lib/odin/vendor/wgpu/lib/wgpu-linux-x86_64-release
        mkdir -p $dest
        unzip -qo ${wgpu} -d $dest
        echo 29.0.1.1 > $dest/VERSION
        makeWrapper $out/lib/odin/odin $out/bin/odin --set-default ODIN_ROOT $out/lib/odin/ --prefix PATH : ${lib.makeBinPath [pkgs.clang pkgs.lld]}
      '';
    };

    # What the window opens with dlopen.
    runtime = with pkgs; [
      vulkan-loader
      mesa
      libxkbcommon
      wayland
      libx11
      libxcb
      libxcb-cursor
      fontconfig
      freetype
      dbus
    ];

    # APP_VERSION of src/main.odin
    version = let
      line = lib.findFirst (lib.hasPrefix "APP_VERSION ::") "" (lib.splitString "\n" (builtins.readFile ./src/main.odin));
    in
      builtins.head (builtins.match ''APP_VERSION :: "([^"]+)".*'' line);

    # The viewer, built from this tree as the release is: viewertool build release.
    modus-viewer = pkgs.stdenv.mkDerivation {
      pname = "modus-viewer";
      inherit version;
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.difference ./. (lib.fileset.maybeMissing ./build);
      };
      # the crates of the toolkit's native library, vendored: cargo makes no request
      cargoDeps = pkgs.rustPlatform.importCargoLock {lockFile = ./ext/gui_toolkit/native/gt/Cargo.lock;};

      nativeBuildInputs = [odin pkgs.cargo pkgs.rustc pkgs.clang pkgs.lld pkgs.autoPatchelfHook pkgs.makeWrapper];
      buildInputs = [pkgs.fontconfig pkgs.freetype pkgs.stdenv.cc.cc.lib];
      runtimeDependencies = runtime;
      # Odin links a foreign library as -l:<absolute path> with -L/, which the purity check of the linker wrapper drops
      NIX_ENFORCE_PURITY = 0;
      MODUS_SOURCE = "${modus}";

      configurePhase = ''
        runHook preConfigure
        export HOME="$TMPDIR"
        mkdir -p "$HOME/.cargo"
        cat > "$HOME/.cargo/config.toml" <<EOF
        [source.crates-io]
        replace-with = "vendored-sources"
        [source.vendored-sources]
        directory = "$cargoDeps"
        EOF
        export CARGO_NET_OFFLINE=true
        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild
        mkdir -p build
        odin run tools/viewertool -collection:gt=ext/gui_toolkit/src -out:build/viewertool -- build release
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 build/modus-viewer $out/bin/modus-viewer
        install -Dm644 -t $out/share/doc/modus-viewer LICENSE README.md CHANGELOG.md
        runHook postInstall
      '';

      meta = {
        description = "See and drive the screen of a distant machine, under a key that its owner allows.";
        license = lib.licenses.mit;
        platforms = [system];
        mainProgram = "modus-viewer";
      };
    };

    preCommitCheck = git-hooks.lib.${system}.run {
      package = pkgs.prek;
      src = ./.;
      hooks = {
        alejandra.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
  in {
    packages.${system} = {
      inherit modus-viewer odin;
      default = modus-viewer;
    };
    apps.${system}.default = {
      type = "app";
      program = "${modus-viewer}/bin/modus-viewer";
    };
    checks.${system} = {
      pre-commit = preCommitCheck;
      inherit modus-viewer;
    };
    formatter.${system} = pkgs.alejandra;

    devShells.${system}.default = pkgs.mkShell {
      packages = [odin] ++ (with pkgs; [cargo rustc]) ++ preCommitCheck.enabledPackages;
      buildInputs = [pkgs.fontconfig];
      shellHook =
        preCommitCheck.shellHook
        + ''
          export LD_LIBRARY_PATH=${lib.makeLibraryPath runtime}
          # The modus source that flake.lock pins; set it to a local checkout to build against that one.
          export MODUS_SOURCE=''${MODUS_SOURCE:-${modus}}
        '';
    };
  };
}
