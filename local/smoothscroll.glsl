// Smooth (sub-cell) trackpad scrolling.
//
// Ghostty scrolls in whole cells. The fork carries a patch that keeps the
// leftover sub-cell remainder of a precision scroll and exposes it as
// iPendingScroll; this shader shifts the rendered frame by that remainder so
// the viewport appears to move continuously rather than snapping a line at a
// time.
//
// Requires the `new_window_with_command`-era fork patch set (see
// ~/ghostty/custom/README.md). Ported from ghostty-org/ghostty#3206.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragCoord -= iPendingScroll;
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);
}
