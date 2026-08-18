{
        description = "BCC328 — Construção de Compiladores I";

        inputs = {
                nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
                flake-utils.url = "github:numtide/flake-utils";
        };

        outputs =
                {
                        self,
                        nixpkgs,
                        flake-utils,
                }:
                flake-utils.lib.eachDefaultSystem (
                        system:
                        let
                                pkgs = import nixpkgs { inherit system; };

                                # GHC 9.6.7 — matches base >= 4.18.3.0 required by bcc328.cabal.
                                # The existing dist-newstyle tree was built with ghc-9.6.7.
                                ghc = pkgs.haskell.compiler.ghc96;

                                # Cross-compilation packages targeting riscv64-unknown-linux-gnu.
                                # NOTE: Nix uses the triple "riscv64-unknown-linux-gnu" while Ubuntu
                                # packages use "riscv64-linux-gnu".  If any Haskell source file
                                # hard-codes the Ubuntu prefix, set the environment variable
                                # RISCV_PREFIX=riscv64-unknown-linux-gnu or create a wrapper.
                                riscv = pkgs.pkgsCross.riscv64;

                        in
                        {
                                devShells.default = pkgs.mkShell {
                                        name = "bcc328";

                                        packages = [
                                                # ----------------------------------------------------------------
                                                # Haskell toolchain
                                                # ----------------------------------------------------------------
                                                ghc
                                                pkgs.cabal-install # cabal
                                                pkgs.stack # stack (present in Docker image)
                                                pkgs.haskellPackages.alex # alex  (lexer generator, build-tool)
                                                pkgs.haskellPackages.happy # happy (parser generator, build-tool)

                                                # C libraries required by GHC and common Haskell packages
                                                pkgs.gmp
                                                pkgs.zlib
                                                pkgs.libffi
                                                pkgs.ncurses

                                                # ----------------------------------------------------------------
                                                # WebAssembly toolchain
                                                # ----------------------------------------------------------------
                                                pkgs.wabt # wat2wasm, wasm2wat, wasm-validate, wasm-objdump…
                                                pkgs.wasmtime # wasmtime runtime
                                                pkgs.binaryen # wasm-merge

                                                # ----------------------------------------------------------------
                                                # Lecture notes & slides tooling
                                                # ----------------------------------------------------------------
                                                pkgs.mdbook # mdbook build / mdbook serve
                                                pkgs.pandoc # used by lecture-notes/Makefile

                                                # TeXLive — packages required by lecture-notes/main.tex.
                                                # minted v3 calls pygmentize via -shell-escape; pygments is
                                                # provided by the python3 entry below.
                                                (pkgs.texlive.combine {
                                                  inherit (pkgs.texlive)
                                                    scheme-medium
                                                    minted fvextra catchfile xstring upquote
                                                    stmaryrd
                                                    tcolorbox environ trimspaces
                                                    algorithms algorithmicx algpseudocodex
                                                    fifo-stack varwidth tabto-ltx totcount tikzmark
                                                    lkproof
                                                    titlesec
                                                    newunicodechar
                                                    latexmk
                                                    beamer
                                                    beamertheme-metropolis pgfopts appendixnumberbeamer
                                                    adjustbox collectbox
                                                    mathpartir
                                                    fontawesome5
                                                    ;
                                                })

                                                # ----------------------------------------------------------------
                                                # General utilities (mirrors Docker image)
                                                # ----------------------------------------------------------------
                                                (pkgs.python3.withPackages (ps: [ ps.pygments ]))
                                                pkgs.cmake
                                                pkgs.gnumake
                                                pkgs.git
                                                pkgs.curl
                                                pkgs.wget
                                        ];

                                        # Put alex and happy on PATH so cabal build-tool-depends finds them
                                        # without needing cabal install.
                                        shellHook = ''
                                                export PATH="${pkgs.haskellPackages.alex}/bin:${pkgs.haskellPackages.happy}/bin:$PATH"

                                                echo "╔══════════════════════════════════════════════════════╗"
                                                echo "║  BCC328 — Construção de Compiladores I               ║"
                                                echo "╚══════════════════════════════════════════════════════╝"
                                                echo "  GHC      : $(ghc --version)"
                                                echo "  Cabal    : $(cabal --version | head -1)"
                                                echo "  Alex     : $(alex --version | head -1)"
                                                echo "  Happy    : $(happy --version | head -1)"
                                                echo "  Wasmtime : $(wasmtime --version)"
                                                echo "  RISCV CC : $(riscv64-unknown-linux-gnu-gcc --version | head -1)"
                                                echo ""
                                                echo "  cd workspace && cabal build"
                                        '';
                                };
                        }
                );
}
