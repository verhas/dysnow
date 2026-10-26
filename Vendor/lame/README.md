# LAME

The MP3 encoder, for saving speech as MP3, from <https://lame.sourceforge.io>,
GNU Lesser General Public License 2.0 or later.

- `include/lame.h`: the header of the release below, unchanged.
- `include/module.modulemap`: makes it a Swift module, `Lame`.
- `lib/`: the static library, not kept in git. `build.sh` downloads the
  source on the first build, checks its SHA-256, and builds it for arm64 and
  x86_64.

Release: 3.100, `lame-3.100.tar.gz`.

LAME is linked statically. The LGPL asks that users can relink the app with
another build of LAME: Dysnow's source is public, and `build.sh` builds it
with whatever is in `lib/`.
