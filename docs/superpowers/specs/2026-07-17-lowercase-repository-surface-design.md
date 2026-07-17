# lowercase repository surface design

## goal

make the private github repository surface lowercase while preserving exact technical names required by released artifacts and executable commands.

## scope

- rename `ubranch/GigaType` to `ubranch/gigatype`
- lowercase the github repository description
- add lowercase topics: `speech-to-text`, `windows`, `cuda`, `gigaam`, `tauri`, and `rust`
- lowercase README prose and headings
- update repository URLs in `README.md`, `BUILD.md`, and `AGENTS.md`
- update the local `private` remote after the github rename

## preserved contracts

- keep exact released filenames such as `GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe`
- keep exact executable and command spelling such as `GigaType.exe`
- keep hashes, revisions, version strings, paths, code, and identifiers unchanged
- keep release tag `v0.9.3-gigatype.1` and its four published assets unchanged
- do not rename application binaries, package identifiers, source symbols, model identifiers, or shipped asset names

## rollout

1. edit repository documentation and validate preserved tokens
2. commit and push documentation changes to private `main`
3. rename the github repository and update description/topics
4. update the local `private` remote URL
5. verify repository metadata, default branch, release tag, asset count, and server-side asset digests

## acceptance

- github repository name is `gigatype`
- description and all repository topics are lowercase
- README prose and headings are lowercase
- exact filenames, commands, hashes, and identifiers remain correct
- repository URL references use `https://github.com/ubranch/gigatype`
- release `v0.9.3-gigatype.1` still points to the same commit and retains four verified assets
