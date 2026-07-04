# Gooey Context Menu Performance

The transition avoids per-frame hierarchy rendering. The source snapshot is captured once, while the readable menu stays at its final layout size. Gooey motion is rendered by frame/corner updates on the temporary shell plus `CAShapeLayer` bridge paths.

Hot-path work:

- one display link per active transition;
- `CAShapeLayer.path` updates for connector and morph surface;
- one temporary shell frame/corner update;
- no Auto Layout in display-link updates;
- no repeated `UIVisualEffectView` creation per frame.

Cleanup requirements:

- display link invalidates on finish/cancel;
- overlay removes itself on finish/cancel;
- source/menu alpha and interaction are restored on cancellation;
- controller cleanup remains idempotent.

The `.gooey` path intentionally does not apply private displacement filters to menu snapshots or row content. Optical emphasis is handled by non-interactive overlay layers so text and icons stay readable during close.
