# AetherList Port Notes

## Source Scope Reviewed

- `TelegramMessenger/Telegram-iOS/submodules/Display/Source/ListView.swift`
- `ListViewItem.swift`
- `ListViewItemNode.swift`
- `ListViewTransactionQueue.swift`
- `ListViewScroller.swift`
- `ListViewIntermediateState.swift`
- `ListViewFloatingHeaderNode.swift`
- `ListViewItemHeader.swift`
- `ListViewOverscrollBackgroundNode.swift`
- `ListViewReorderingGestureRecognizer.swift`
- `TelegramUI/Sources/ChatHistoryListNode.swift`
- `ItemListUI/Sources/ItemListControllerNode.swift`
- `ItemListUI/Sources/ItemListItem.swift`

The local workspace does not contain `submodules/`, so the source pass used the upstream GitHub repository as the primary reference. This implementation is adapted/clean-room for AetherUI and does not copy Telegram app modules, ASDK/Texture symbols, assets, branding, or SwiftSignalKit dependencies.

## Type Mapping

| Telegram iOS | AetherUI |
| --- | --- |
| `ASDisplayNode` | `UIView` / `CALayer`, primarily `AetherListItemNode` |
| `ASImageNode` | `UIImageView` / caller-owned UIKit image views |
| `ASScrollNode` / `ListViewScroller` | `AetherListScroller` backed by `UIScrollView` physics |
| `ListViewItem` | `AetherListItem` |
| `ListViewItemNode` | `AetherListItemNode` / `AetherListItemView` |
| `ListViewItemNodeLayout` | `AetherListItemNodeLayout` / `AetherListItemLayout` |
| async layout `layout + apply` | `AetherListPreparedItemLayout` + `AetherListLayoutTask` |
| `ListViewTransactionQueue` | serialized `AetherListTransaction` path + VSync drain via `AetherListDisplayLinkDriver` |
| `ListViewStateOperation` | `AetherListStateOperation` |
| `ControlledTransition` | `ContainedViewLayoutTransition` and UIKit/CALayer animations |
| SwiftSignalKit signals | closures and cancellable layout tasks |
| floating headers | `AetherListItem.isFloatingHeader`, `headerId`, `headerAffinity` |

## Ported In This Stage

- Manual frame-based virtualization with visible + preload range.
- UIScrollView-native pan/deceleration/bounce physics with item views mounted in an Aether backing container.
- Stable item identity, reuse identifiers, layout cache, and reuse pool.
- Transaction API for insert/delete/update/move/scroll/updateSizeAndInsets.
- Stationary anchor preservation and bottom-anchored chat-style behavior already present in the local implementation.
- Sticky/floating headers with reuse/cache integration.
- Insertion/deletion/update animations, including the existing Aether dust dissolve path.
- Display-link scheduling for queued non-low-latency transactions.
- Debug instrumentation counters, signposts, and optional overlay.
- Overscroll callbacks/background hooks and optional custom vertical indicator.
- Reordering lifecycle callbacks, haptic hook, and edge auto-scroll.
- VoiceOver scroll actions and visible-node accessibility ordering.
- Dynamic Type invalidation hook.
- Unit-testable range/remap/intermediate-state/scroll math.
- Demo stress data set with 10k mixed-height rows.

## Resolved Since Initial Port

- Async item layout now keeps a prepared layout cache and applies prepared `layout + apply` results to visible nodes on main when the item is still current. UIKit-backed node creation remains main-thread by design.
- `AetherListScroller` keeps UIKit's native pan/bounce/deceleration path; `backingView` is its single hosted content surface, so item nodes are not direct scroll-view subviews.
- Reorder now uses a lifted snapshot plus placeholder slot, keeps the source node protected from reuse while validation is pending, and supports `validateReorder(from:to:completion:)` with rollback animation on rejection.
- `headerAffinity == .bottom` now has visual bottom-pinning behavior and keeps the pinned node alive outside the regular preload range.
- Layout/prepared caches and reuse pools are evicted on memory pressure; Dynamic Type and width changes also clear prepared layout state.
- Transaction remap/order math is available through `AetherListTransactionPlanner`; `AetherListIntermediateState` now covers pure stable-id state replay, before/after snapshots, and stationary-anchor offset deltas.
- `stationaryItemRange` now tracks the anchored item by stable id instead of preserving a stale numeric index after insert/delete shifts.
- `AetherListAccessoryItem` renders `accessoryItem` and `headerAccessoryItem` through the base node host, with automatic update/reuse cleanup.
- `.visible` scroll targeting now respects top/bottom content insets, matching the node-based `ensureItemNodeVisible` path.
- List-owned tap/reorder gestures now respect node-level hit testing, nested `UIControl`/custom gesture descendants, and an app-provided `itemGestureShouldBegin` gate.
- Sticky headers now publish pinned/floating/flashing state to nodes, keep pushed headers above regular rows, and use visual z/subview ordering for list gesture hit testing.
- Overscroll distance and custom scroll-indicator math now use true scrollable bounds, avoid false bottom overscroll on short content, and support an optional `customScrollIndicatorFollowsOverscroll` bounce mode.
- Node replay animation policy is now centralized in `AetherListNodeReplayPlan`: insertion, deletion, update, survivor-frame animation timing, particle-dissolve slide stretching, and Reduce Motion handling are testable outside UIKit.
- Previous-node reuse and duplicate target eviction during transaction materialization are now routed through `AetherListNodeMaterializationPlanner`, which emits immutable commands that `AetherListView` executes against UIKit nodes.
- Update-node materialization now uses `AetherListUpdateMaterializationCommandPlanner`: previous-node reuse, current-node fallback, invalid-index skipping, and estimated-height fallback are decided without UIKit before the live executor updates mounted nodes.
- Visible-node materialization now uses `AetherListVisibleNodeMaterializationCommandPlanner`: loaded indices are skipped, inserted previous nodes are reused when available, and remaining visible holes mount through reuse/create commands.
- Sticky-header refresh now uses `AetherListStickyHeaderCommandPlanner`: pinned top/bottom selection, missing pinned-node materialization, target frames, sticky state, z-order, and bring-to-front decisions are computed without UIKit before the live executor applies them.
- Scroll-time virtualization now uses `AetherListVirtualizationCommandPlanner`: recycle, protected reorder nodes, pinned headers outside preload, visible-index mounting, and frame repositioning are planned without UIKit before the live executor mutates nodes.
- Async layout prefetch scheduling now uses `AetherListAsyncLayoutCommandPlanner`: stale pending layout tasks outside the loaded/preload range are cancelled, cached/pending/synchronous rows are skipped, and eligible rows are selected for off-main preparation without UIKit.
- Displayed-range lifecycle now uses `AetherListVisibilityLifecycleCommandPlanner`: loaded/visible ranges, first fully visible item metadata, accessibility traversal order, visible-view counters, and displayed-range notifications are produced from a UIKit-free node snapshot before the live executor calls app/debug hooks.
- Large/incrementally loaded lists can now model unloaded top/bottom extents with `AetherListVirtualContentInsets`. `AetherListContentMetricsPlanner` combines real row heights, item offset insets, and virtual extents into offsets/content height, and `AetherListView` compensates content offset when virtual top changes so prepended history does not visually jump.
- Concrete node mount/configuration now goes through a single `mountNode` executor, shared by transaction replay, virtualization, and sticky-header materialization.
- `executeTransaction` is now an explicit pipeline of phase executors: size/insets, loaded-node snapshot, model mutation, node materialization, frame replay, sticky-header refresh, and scroll anchoring.
- Frame replay now flows through generic replay commands and `AetherListFrameReplayCommandExecuting`; tests run the same command stream against a non-UIKit recorder before the UIKit executor applies it to real nodes.
- Size/inset updates and scroll anchoring now use the same command/executor split: pure planners decide resize, cache invalidation, inset, explicit scroll, stationary-anchor, and bottom-anchor commands, while UIKit executors apply them to the live scroll view.
- Transaction model mutation now uses `AetherListModelMutationCommandPlanner`: delete/move/insert ordering, index clamping, estimated insert heights, and insertion animation metadata are decided without UIKit before the live list executor applies the commands to `items`, `itemHeights`, and visible-node removal bookkeeping.
- Keyboard, safe-area, and input-overlay inset changes now route through `AetherListEffectiveInsetsPlanner`: `stackFromBottom` top padding, old top-inset compensation, scroll-indicator insets, and bottom-anchor preservation are computed before UIKit applies the animated content-inset/content-offset update. Twitty's dialog and ChatV2 screens use the same `AetherListView.updateInsets` path, so their input bar / keyboard transitions inherit this behavior from the framework.
- Paged/infinite loading now has a framework-level boundary trigger API. `AetherListBoundaryTriggerPlanner` evaluates top/bottom distance and item-threshold rules from the current visible/loaded range, `AetherListView.boundaryReached` deduplicates repeated edge hits, and Twitty Dialog / ChatV2 use that callback instead of screen-local scroll-offset math.

## Remaining Follow-Ups

- No open ListView-parity blocker remains in the current AetherUI/Twitty scope. The list-owned math and lifecycle pieces called out during the port are now centralized in framework planners/executors instead of living in app screens.
- The optional custom scroll indicator is intentionally vertical because `AetherListView` is a vertical list.
- A fully list-owned data-source object that fetches and mutates rows internally is intentionally out of scope. AetherList keeps caller-owned transactions and supplies boundary triggers plus `virtualContentInsets` for paged histories.
- ASDK/Texture integration remains intentionally out of scope; this port stays UIKit/CALayer based.

## License / Compliance

- No Telegram branding, assets, icons, app-specific entities, SwiftSignalKit, or ASDK/Texture dependencies were added.
- No verbatim Telegram `ListView` source was copied in this change. If future changes copy any non-trivial source fragment, preserve the original file notice and record the upstream path and commit.
- Telegram-iOS README asks downstream apps not to use Telegram branding/assets and to comply with applicable licenses. AetherUI should keep this port as an adapted implementation unless a full license review is performed for any direct source import.
