# Contributing

## Tests

You need Lua 5.1, the version the game uses. Run these from the repository root:

```sh
lua5.1 tests/run.lua                # run the tests
lua5.1 tests/run.lua /tmp/renders   # also write each UI view to that existing folder as HTML
```

`tests/harness.lua` is a strict fake of the client API. It checks logic and layout but can't prove behavior in the real game, so try changes in-game too.

## How time is sorted

Once per second the addon assigns the last second to exactly one category. The first match wins:

| Priority | Category | Detected by |
| --- | --- | --- |
| 1 | Fighting | Game's in-combat flag |
| 2 | AFK | AFK flag. The idle stretch leading up to the flag moves to AFK as well |
| 3 | Dead | Dead or ghost |
| 4 | Gathering | Casting Mining, Herb Gathering, Skinning or Fishing |
| 5 | Crafting | Casting a tradeskill spell |
| 6 | Traveling | Moving, or on a flight path |
| 7 | Crafting | Standing with a profession window open |
| 8 | NPCs & Trade | Quest and gossip dialogs, vendor, trainer, mail, bank, auction house, trade |
| 9 | Eating & Drinking | Standing with a food or drink buff |
| 10 | Idle | None of the above |

Loading is measured separately, as the time between leaving and entering the world.

## Forever's addon restrictions

Forever uses Midnight's addon restrictions, so the combat log isn't available. Everything comes from player state and events, and every game read tolerates secret values and missing APIs.

The gathering spell IDs in `Classifier.lua` are unverified on Forever. The literal spell names cover English and German.

## Releasing

Pushing a tag starts `.github/workflows/release.yml`. It runs the tests, builds the ZIP with the [BigWigs packager](https://github.com/BigWigsMods/packager), then uploads it to GitHub and CurseForge. The tag name becomes the version in the `.toc`.

One-time setup:

1. Create the project at [authors.curseforge.com](https://authors.curseforge.com) and pick a license. Paste `docs/curseforge-description.md` as the description and upload `assets/screenshots/` to the gallery.
2. Add its ID to `ForeverTimeTracker/ForeverTimeTracker.toc` as `## X-Curse-Project-ID: 123456`. Without this line the packager skips CurseForge.
3. Create an API token at [legacy.curseforge.com/account/api-tokens](https://legacy.curseforge.com/account/api-tokens) and save it as the repository secret `CF_API_KEY`.

For each release:

1. Add the new version to `CHANGELOG.md`. It becomes the changelog on CurseForge.
2. If the game patched, update `## Interface` in the `.toc`.
3. Tag and push. A tag containing `beta` or `alpha` publishes as that release type:

```sh
git tag v0.1.0-beta.1
git push origin main v0.1.0-beta.1
```
