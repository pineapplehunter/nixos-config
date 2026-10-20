// Requires the local iPendingScroll uniform added by the Ghostty overlay.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragCoord -= iPendingScroll;
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);
}
