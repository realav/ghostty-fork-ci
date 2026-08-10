# ghostty-fork-ci

CI that builds a patched [Ghostty](https://github.com/ghostty-org/ghostty) for
macOS arm64. None of Ghostty's history lives here — only the patches, the
upstream pin, and the workflow that puts them together.

Same shape as [zed-fork-ci](https://github.com/realav/zed-fork-ci).

## Layout

| Path                              | Purpose                                                  |
| --------------------------------- | -------------------------------------------------------- |
| `patches/*.patch`                 | The fork's source changes, `git am`-able onto upstream   |
| `.fork-base`                      | Upstream commit the patches are known to apply to        |
| `.github/workflows/build-mac.yml` | Clone upstream → apply patches → build → upload artifact |
| `local/install.sh`                | Download the latest build, re-sign, install              |
| `local/make-patches.sh`           | Regenerate `patches/` from a local fork checkout         |
| `local/make-signing-cert.sh`      | Create the local signing certificate (run once)          |
| `local/smoothscroll.glsl`         | Shader for the smooth-scrolling patch                    |

## Install a build

```sh
./local/install.sh            # latest successful run
./local/install.sh <run-id>   # a specific run
```

Quit Ghostty first — the script refuses to overwrite a running bundle.

## Patches

**`new_window_with_command` / `new_tab_with_command`** — keybind actions that
launch a window or tab running a given command:

```
keybind = cmd+escape=new_tab_with_command:claude
keybind = cmd+shift+escape=new_window_with_command:claude
```

Upstream has no keybind action that can launch a command: `new_window` and
`new_tab` take no argument, and `ghostty +new-window` (which does accept
`--command`) is Linux-only, because the macOS apprt returns `false` for every
IPC action. Because these resolve inside libghostty's key-binding layer they
fire regardless of what is running in the focused surface, which shell-level
workarounds can't do.

**Smooth (sub-cell) scrolling** — ported from
[#3206](https://github.com/ghostty-org/ghostty/discussions/3206). Ghostty
computes the sub-cell remainder of a precision scroll and then discards it:
`poff - (poff / cell_size) * cell_size` is always zero because the division
isn't truncated first. Truncating keeps it, and a shader shifts the frame by it.

Enable with `custom-shader = smoothscroll.glsl` (copy `local/smoothscroll.glsl`
to `~/.config/ghostty/`). Inert without it.

It **cannot** work in alternate-screen applications — Claude Code with a real
session, nvim, less. Measured over 2275 scroll events: the alternate screen has
no scrollback, the application takes the wheel and repaints itself, and
Ghostty's viewport never moves, so there is nothing to smooth. Fixing that would
need a protocol for applications to report fractional scroll, which is what
[#2355](https://github.com/ghostty-org/ghostty/discussions/2355) was closed
over. Note an _idle_ Claude Code session stays on the primary screen with mouse
tracking off, so testing without scrollable content gives the opposite answer.

## Signing

CI signs ad-hoc on purpose — the certificate never leaves the local machine.

That matters because macOS TCC keys permission grants on code signing identity,
and an ad-hoc signature is identified by the binary hash. Every build would look
like a new app and re-prompt forever ("Ghostty.app would like to access data
from other apps"). `local/install.sh` re-signs with a stable certificate on
download, so the designated requirement becomes a certificate hash and one
"Allow" sticks.

Run `local/make-signing-cert.sh` once to create it.

## Space

The build runs entirely on the runner. Nothing but patches lives here, and no
build cache accumulates locally.

`-Dxcframework-target=native` builds only the arm64 macOS slice. The default
(`universal`) also builds x86_64, iOS and the iOS simulator — slices that are
never run, and which are what make a local `.zig-cache` reach tens of GB.

## Updating the patches

The workflow's scheduled run follows upstream `main`. If upstream drifts far
enough that `git am` fails, the build fails loudly — that's the signal to
refresh:

```sh
./local/refresh-patches.sh          # rebase onto upstream main
./local/refresh-patches.sh <ref>    # or onto a specific ref
```

It clones upstream into a temp directory, replays the patches, rebases, and
writes `patches/` and `.fork-base` back. No persistent fork checkout is needed —
this repo is self-contained. On a conflict the clone is kept and the script
prints how to finish by hand.

Then commit, push, and run the workflow to confirm it still builds.
