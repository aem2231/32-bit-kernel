{
  description = "x86 Bare Bones OS development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        cross    = pkgs.pkgsCross.i686-embedded;
        cc       = cross.buildPackages.gcc;
        binutilsPkg = cross.buildPackages.binutils;

        myos = pkgs.stdenv.mkDerivation {
          pname = "myos";
          version = "0.1.0";

          # Place flake.nix alongside boot.s, kernel.c, linker.ld
          src = ./.;

          nativeBuildInputs = [ cc binutilsPkg pkgs.grub2 pkgs.xorriso ];

          buildPhase = ''
            i686-elf-as boot.s -o boot.o

            i686-elf-gcc -c kernel.c -o kernel.o \
              -std=gnu99 -ffreestanding -O2 -Wall -Wextra

            i686-elf-gcc -T linker.ld -o myos \
              -ffreestanding -O2 -nostdlib \
              boot.o kernel.o -lgcc

            grub-file --is-x86-multiboot myos \
              || { echo "ERROR: invalid multiboot header" >&2; exit 1; }

            mkdir -p isodir/boot/grub
            cp myos isodir/boot/myos
            cat > isodir/boot/grub/grub.cfg <<'EOF'
menuentry "myos" {
    multiboot /boot/myos
}
EOF
            grub-mkrescue -o myos.iso isodir
          '';

          installPhase = ''
            install -Dm755 myos     $out/boot/myos
            install -Dm644 myos.iso $out/iso/myos.iso
          '';
        };

      in {
        packages.default = myos;
        packages.myos    = myos;

        apps.default = {
          type    = "app";
          program = toString (pkgs.writeShellScript "run-myos" ''
            exec ${pkgs.qemu}/bin/qemu-system-i386 \
              -cdrom ${myos}/iso/myos.iso "$@"
          '');
        };

        apps.qemu-kernel = {
          type    = "app";
          program = toString (pkgs.writeShellScript "run-myos-kernel" ''
            exec ${pkgs.qemu}/bin/qemu-system-i386 \
              -kernel ${myos}/boot/myos "$@"
          '');
        };

        devShells.default = pkgs.mkShell {
          name = "osdev-shell";
          packages = [
            cc binutilsPkg
            pkgs.nasm
            pkgs.grub2
            pkgs.xorriso
            pkgs.qemu
            pkgs.gdb
          ];
          shellHook = ''
            echo ""
            echo "  x86 OSDev shell — i686-elf toolchain ready"
            echo ""
            echo "  Build:"
            echo "    i686-elf-as boot.s -o boot.o"
            echo "    i686-elf-gcc -c kernel.c -o kernel.o -std=gnu99 -ffreestanding -O2 -Wall -Wextra"
            echo "    i686-elf-gcc -T linker.ld -o myos -ffreestanding -O2 -nostdlib boot.o kernel.o -lgcc"
            echo ""
            echo "  Verify:  grub-file --is-x86-multiboot myos && echo ok"
            echo "  Run:     qemu-system-i386 -kernel myos"
            echo ""
          '';
        };
      }
    );
}
