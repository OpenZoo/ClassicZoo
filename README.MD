# ClassicZoo, demo recording

This is a version of ClassicZoo intended to support demo recording and (eventually) verifiable high-score runs.

The goal is to get ClassicZoo to transparently record a demo of a player's current run, with these demos following saves and restores. When the player dies and is asked to submit a high score, the demo will then act as proof that the player attained that score. This, in turn, would allow shared scoreboards that can't simply be spammed by submitting a bunch of fake high scores.

For more information about ClassicZoo, please visit the [wiki page](https://zeta.asie.pl/wiki/doku.php?id=release:classiczoo).

To find compilation and configuration information, see `DEVDOC/`.

To compile with Turbo Pascal, copy the contents of the main Turbo Pascal directory to `VENDOR/TP` and run `./build.sh`. This build method requires dosbox.