# Installing stemma

stemma is two programs: `stemma`, the command-line tool, and
`stemma-server`, the browser UI. Neither needs anything else at run time.

## Prebuilt binaries

Each [release](https://github.com/HallowXIII/stemma/releases) has an
archive for Linux (x86-64), macOS (Apple silicon and Intel) and Windows
(x86-64). It holds the two programs, the documentation and the Romance
example. Unpack it anywhere and run the programs from there, or put them
somewhere on your `PATH`.

```sh
cd stemma-linux-x86_64
./stemma -d examples/romance build
./stemma-server -d examples/romance      # then open http://127.0.0.1:8737
```

**Windows.** In PowerShell or the command prompt, from the unpacked
folder:

```
.\stemma.exe -d examples\romance build
.\stemma-server.exe -d examples\romance
```

SmartScreen may warn about a program from an unknown publisher, since the
binaries aren't signed: choose *More info*, then *Run anyway*. If IPA
letters show as boxes, the console's font lacks them; choose another in
the terminal's settings.

**macOS.** The binaries aren't signed, so Gatekeeper refuses a download
until its quarantine flag is removed:

```sh
xattr -dr com.apple.quarantine stemma-macos-arm64
```

## Building from source

You need GHC 9.10 and cabal, which [GHCup](https://www.haskell.org/ghcup/)
installs on every platform, and about 4 GB of disk space. The first build
compiles stemma's dependencies and takes ten to twenty minutes.

1. Install GHCup, following the instructions on its page. On Windows that
   is one command pasted into PowerShell (not as administrator); accept
   the defaults, which include the MSYS2 toolchain it needs. On Linux it
   lists the system packages to install first (a C compiler, GMP and so
   on); stemma also needs zlib's headers (`zlib1g-dev` on Debian and
   Ubuntu, `zlib-devel` on Fedora). Open a new terminal afterwards.

2. Select the GHC that stemma is tested with:

   ```sh
   ghcup install ghc 9.10.3
   ghcup set ghc 9.10.3
   ```

3. Get the source, with git or from *Code > Download ZIP* on GitHub:

   ```sh
   git clone https://github.com/HallowXIII/stemma.git
   cd stemma
   ```

4. Build and install both programs:

   ```sh
   cabal update
   cabal install exe:stemma exe:stemma-server
   ```

   They go into cabal's `bin` directory: `~/.local/bin` or `~/.cabal/bin`
   on Linux and macOS, `C:\cabal\bin` with GHCup on Windows. GHCup's
   installer offers to put it on your `PATH`.

5. Try the example:

   ```sh
   stemma -d examples/romance build
   stemma-server -d examples/romance
   ```

To update, `git pull` and repeat step 4 with `--overwrite-policy=always`.
`cabal test` checks that the example reproduces its attested forms.

## Nix

`nix profile add github:HallowXIII/stemma`, or the flake's overlay; see
the [README](../README.md#usage).

## Extras

- [Typst](https://typst.app), to typeset dictionaries and grammars from a
  build (`stemma typst`).
