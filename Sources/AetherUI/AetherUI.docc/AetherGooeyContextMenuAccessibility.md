# Gooey Context Menu Accessibility

The gooey overlay is visual-only:

- overlay views are not accessibility elements;
- snapshots set `accessibilityElementsHidden = true`;
- connector and debug geometry are hidden from VoiceOver;
- real menu rows keep their existing labels and traits.

Reduce Motion:

- disables elastic lens/connector emphasis;
- shortens the transition;
- uses a simpler fade/scale handoff.

Reduce Transparency:

- increases tint opacity;
- keeps connector readable without relying only on blur.

Increased Contrast:

- increases stroke alpha around the transitional surface.

Focus restoration remains owned by the existing context menu/source lease pipeline.
