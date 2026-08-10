# Custom Ghostty fork

A fork of [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) that tracks
upstream `main` and carries a small set of local patches.

## Branches

| Branch   | Purpose                                                     |
| -------- | ----------------------------------------------------------- |
| `main`   | Clean mirror of upstream `main`. Never commit here.         |
| `custom` | `main` + the patches below. This is what you build and run. |

Remotes: `origin` = your fork, `upstream` = ghostty-org/ghostty.

## Patches

### 1. `new_window_with_command` keybind action

Upstream has no keybind action that can launch a window running a specific
command — `new_window` takes no argument, and `ghostty +new-window` (which does
accept `--command`) is Linux-only because the macOS apprt returns `false` for
all IPC.

This adds an action that takes a command:

```
keybind = cmd+escape=new_window_with_command:claude
```

The command is applied to the new window's first surface, overriding the
`command` config for that window only. Working directory inheritance and focus
behavior are unchanged from `new_window`.

Because it resolves inside libghostty's key-binding layer, it fires no matter
what is running in the focused surface — including full-screen TUIs that would
otherwise swallow the key.

Files touched:

- `src/input/Binding.zig` — the action and its scope
- `src/input/command.zig` — excluded from the command palette (takes a free-form argument)
- `src/apprt/action.zig` — `NewWindowCommand` payload and its C ABI
- `include/ghostty.h` — matching enum, struct, and union member
- `src/App.zig`, `src/Surface.zig` — routes the command to the apprt action
- `src/apprt/gtk/class/application.zig` — GTK support (uses its existing command override)
- `macos/Sources/Ghostty/Ghostty.Action.swift` — decodes the payload
- `macos/Sources/Ghostty/Ghostty.App.swift` — sets `command` on the new surface config

Additive by design: no existing type or behavior changes, which keeps rebases quiet.

### 2. Smooth (sub-cell) scrolling

Ported from [ghostty-org/ghostty#3206](https://github.com/ghostty-org/ghostty/discussions/3206).
Upstream has no native support and the older request
([#2355](https://github.com/ghostty-org/ghostty/discussions/2355)) was closed as
"not directly actionable", so this hack is the only implementation that exists.

Ghostty scrolls a whole cell at a time. It computes the leftover sub-cell
remainder of a precision (trackpad) scroll and then immediately throws it away —
`poff - (poff / cell_size) * cell_size` is always zero because the division
isn't truncated first. Truncating keeps the remainder, and a custom shader
shifts the frame by it so the viewport moves continuously.

Files touched:

- `src/Surface.zig` — `@trunc` the cell count so the remainder survives; compute
  the clamped render offset (`mouse.smooth_scroll_y`)
- `src/terminal/PageList.zig` — `pinIsActive` made public
- `src/renderer/shadertoy.zig`, `src/renderer/shaders/shadertoy_prefix.glsl` —
  `iPendingScroll` uniform
- `src/renderer/generic.zig` — feed the uniform each frame

Enable with `custom-shader = smoothscroll.glsl` (the shader lives in
`~/.config/ghostty/`). `custom-shader-animation` already defaults to `true`.

**Deviation from the original patch:** upstream's version read the live terminal
(`mouse_event` mode, scrollback boundaries) from inside the renderer, which runs
on its own thread — a data race. Here that logic runs in `scrollCallback` on the
app thread under the renderer lock, and the render thread only reads one scalar.

**Known limitations** (inherited from the original, per its author):

- Requires a custom shader, so every frame goes through an offscreen pass.
- Text selection is off by the sub-cell offset while partially scrolled.
- No extra row is rendered at the top/bottom edge, so a partial scroll can show
  a sliver of background.
- Typing doesn't reset the pending offset.
- Uses `@fieldParentPtr` to reach the Surface from the renderer, which assumes
  the renderer is always embedded in a Surface.

**It cannot work in alternate-screen applications, and that is not fixable here.**
Measured across 2275 scroll events in a real Claude Code session: `alt=true`,
`mouse_event=.any`, `at_bottom=true` and the offset zeroed on every single one.
The alternate screen has no scrollback, the application takes the wheel and
redraws its own transcript, and Ghostty's viewport never moves. The offset
shifts _Ghostty's_ viewport, so when the viewport isn't what's moving there is
nothing to smooth — applying it anyway would only smear the application's UI.
The same applies to nvim, less and htop. Fixing it would need a terminal
protocol for applications to report fractional scroll, which is exactly what
[#2355](https://github.com/ghostty-org/ghostty/discussions/2355) was closed over.

Note that an idle Claude Code session with no transcript stays on the primary
screen with mouse tracking off, so testing without scrollable content gives the
opposite (and wrong) answer.

To turn it off, comment out `custom-shader` in the config — the Zig changes are
inert without it.

## Builds run in CI

Day-to-day builds happen in
[realav/ghostty-fork-ci](https://github.com/realav/ghostty-fork-ci), which holds
the patches and a macOS runner workflow. Install a build with its
`local/install.sh` — it re-signs with the local certificate on download, so
permission grants survive.

This checkout is only needed to *develop* the patches (rebasing onto upstream,
resolving conflicts). It is otherwise disposable — a local build's `.zig-cache`
reaches tens of GB.

## Build locally

```sh
./custom/build.sh            # build + install to /Applications/Ghostty.app
./custom/build.sh --no-install
```

Builds only the native arm64 slice (`-Dxcframework-target=native`); the default
universal build also produces x86_64, iOS and iOS-simulator slices that are
never run. Delete `.zig-cache`, `zig-out`, `zig-pkg` and `macos/build` when
done — they are pure cache.

`/usr/local/bin/libtool` is GNU libtool and breaks the build, so the script puts
`/usr/bin` first in `PATH` to pick up Apple's.

Requires Zig 0.16.0 (`brew install zig`) and Xcode.

## Track upstream

```sh
./custom/rebase.sh
```

Fast-forwards `main` to `upstream/main`, then rebases `custom` on top. `git rerere`
is enabled, so a conflict resolved once is replayed automatically next time.

If it stops on a conflict: fix, `git add`, `git rebase --continue`. To bail out,
`git rebase --abort`.

Rebuild afterwards — a self-built app has no auto-update.
