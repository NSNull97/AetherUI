import XCTest
import UIKit
@testable import AetherUI

final class AetherListCoreTests: XCTestCase {
    func testDeletionRemapIndices() {
        let remap = AetherListFrameMetrics.deletionRemap(itemCount: 8, deletedIndices: [1, 4])
        XCTAssertEqual(remap, [
            2: 1,
            3: 2,
            5: 3,
            6: 4,
            7: 5
        ])
    }

    func testInsertionRemapIndices() {
        let remap = AetherListFrameMetrics.insertionRemap(survivingIndices: [0, 1, 2, 3], insertedIndices: [0, 2])
        XCTAssertEqual(remap, [
            0: 1,
            1: 3,
            2: 4,
            3: 5
        ])
    }

    func testVisibleRangeComputationIncludesPreload() {
        let heights: [CGFloat] = [20, 40, 60, 80, 100]
        let offsets = AetherListFrameMetrics.rebuildOffsets(heights: heights, offsetInsets: .zero).offsets
        let range = AetherListFrameMetrics.visibleRange(
            offsets: offsets,
            heights: heights,
            viewportTop: 55,
            viewportHeight: 100,
            preloadPages: 0.5
        )
        XCTAssertEqual(range, 0..<5)
    }

    func testEstimatedOffsetsFallback() {
        let result = AetherListFrameMetrics.rebuildOffsets(
            heights: [44, 60, 32],
            offsetInsets: UIEdgeInsets(top: 10, left: 0, bottom: 7, right: 0)
        )
        XCTAssertEqual(result.offsets, [10, 54, 114])
        XCTAssertEqual(result.totalHeight, 153)
    }

    func testScrollToBottomTargetCalculation() {
        let offsets = AetherListFrameMetrics.rebuildOffsets(heights: [40, 60, 120], offsetInsets: .zero).offsets
        let target = AetherListFrameMetrics.scrollOffset(
            index: 2,
            position: .bottom(offset: 12),
            offsets: offsets,
            heights: [40, 60, 120],
            nodeInsets: .zero,
            viewportHeight: 100,
            insets: UIEdgeInsets(top: 8, left: 0, bottom: 20, right: 0),
            currentOffset: 0,
            customOverflow: nil
        )
        XCTAssertEqual(target, 152)
    }

    func testVisibleScrollTargetRespectsInsets() {
        let offsets = AetherListFrameMetrics.rebuildOffsets(heights: [40, 40, 40], offsetInsets: .zero).offsets
        let insets = UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)

        let targetForTopCoveredItem = AetherListFrameMetrics.scrollOffset(
            index: 0,
            position: .visible,
            offsets: offsets,
            heights: [40, 40, 40],
            nodeInsets: .zero,
            viewportHeight: 100,
            insets: insets,
            currentOffset: 0,
            customOverflow: nil
        )
        XCTAssertEqual(targetForTopCoveredItem, -10)

        let targetForBottomCoveredItem = AetherListFrameMetrics.scrollOffset(
            index: 2,
            position: .visible,
            offsets: offsets,
            heights: [40, 40, 40],
            nodeInsets: .zero,
            viewportHeight: 100,
            insets: insets,
            currentOffset: 0,
            customOverflow: nil
        )
        XCTAssertEqual(targetForBottomCoveredItem, 40)
    }

    func testTransactionObjectStoresOperations() {
        let item = TestItem(id: 1, height: 44)
        let transaction = AetherListTransaction(
            deleteIndices: [AetherListDeleteItem(index: 0)],
            insertIndicesAndItems: [AetherListInsertItem(index: 0, item: item)],
            options: [.synchronous],
            scrollToItem: AetherListScrollToItem(index: 0, position: .top(offset: 0), animated: false)
        )
        XCTAssertEqual(transaction.deleteIndices.count, 1)
        XCTAssertEqual(transaction.insertIndicesAndItems.count, 1)
        XCTAssertTrue(transaction.options.contains(.synchronous))
        XCTAssertEqual(transaction.scrollToItem?.index, 0)
    }

    func testTransactionPlannerProducesRemaps() {
        let plan = AetherListTransactionPlanner.plan(
            itemCount: 5,
            deleteIndices: [1],
            insertIndices: [0, 2],
            moveIndices: [(fromIndex: 3, toIndex: 1)],
            updateIndices: [2]
        )

        XCTAssertEqual(plan.deletionRemap, [2: 1, 3: 2, 4: 3])
        XCTAssertEqual(plan.insertionRemap, [0: 1, 2: 4, 3: 5, 4: 6])
        XCTAssertTrue(plan.operations.contains(.delete(index: 1)))
        XCTAssertTrue(plan.operations.contains(.insert(index: 0)))
        XCTAssertTrue(plan.operations.contains(.move(fromIndex: 3, toIndex: 1)))
        XCTAssertTrue(plan.operations.contains(.update(index: 2)))
    }

    func testNodeReplayPlanDisablesAnimationsForReduceMotion() {
        let plan = AetherListNodeReplayPlan.make(
            options: [.animateInsertions, .animateAlpha, .crossfade],
            hasForcedInsertionAnimation: true,
            hasParticleDissolveRemoval: true,
            baseDuration: 0.3,
            particleDissolveDuration: 0.72,
            reduceMotionEnabled: true
        )

        XCTAssertFalse(plan.animatesStructuralChanges)
        XCTAssertFalse(plan.usesAlphaAnimations)
        XCTAssertEqual(plan.updateAnimation, .none)
        XCTAssertEqual(plan.survivingFrameAnimation, .none)
        XCTAssertEqual(
            plan.insertionAnimation(
                isNewNode: true,
                forceItemAnimation: true,
                directionHint: .up,
                invertOffsetDirection: true
            ),
            .none
        )
        XCTAssertNil(plan.deletionAnimation(for: .scale))
    }

    func testNodeReplayPlanStretchesSurvivorSlideForParticleDissolve() {
        let regular = AetherListNodeReplayPlan.make(
            options: [.animateInsertions],
            hasForcedInsertionAnimation: false,
            hasParticleDissolveRemoval: false,
            baseDuration: 0.3,
            particleDissolveDuration: 0.72,
            reduceMotionEnabled: false
        )
        let particle = AetherListNodeReplayPlan.make(
            options: [.animateInsertions],
            hasForcedInsertionAnimation: false,
            hasParticleDissolveRemoval: true,
            baseDuration: 0.3,
            particleDissolveDuration: 0.72,
            reduceMotionEnabled: false
        )

        XCTAssertEqual(regular.survivingFrameAnimation, .animated(duration: 0.3, curve: .standard))
        XCTAssertEqual(particle.survivingFrameAnimation, .animated(duration: 0.72, curve: .easeOut))
    }

    func testNodeReplayPlanResolvesInsertionAndDeletionAnimations() {
        let alpha = AetherListNodeReplayPlan.make(
            options: [.animateInsertions, .animateAlpha],
            hasForcedInsertionAnimation: false,
            hasParticleDissolveRemoval: false,
            baseDuration: 0.3,
            particleDissolveDuration: 0.72,
            reduceMotionEnabled: false
        )
        XCTAssertEqual(
            alpha.insertionAnimation(
                isNewNode: true,
                forceItemAnimation: false,
                directionHint: nil,
                invertOffsetDirection: false
            ),
            .alphaFade(duration: 0.1)
        )
        XCTAssertEqual(alpha.deletionAnimation(for: .scale), .fade)
        XCTAssertEqual(
            alpha.deletionAnimation(for: .particleDissolve(tileSize: 2)),
            .particleDissolve(tileSize: 2)
        )

        let item = AetherListNodeReplayPlan.make(
            options: [.requestItemInsertionAnimations, .animateFullTransition],
            hasForcedInsertionAnimation: false,
            hasParticleDissolveRemoval: false,
            baseDuration: 0.3,
            particleDissolveDuration: 0.72,
            reduceMotionEnabled: false
        )
        XCTAssertEqual(item.updateAnimation, .fullTransition(duration: 0.3))
        XCTAssertEqual(
            item.insertionAnimation(
                isNewNode: true,
                forceItemAnimation: true,
                directionHint: .up,
                invertOffsetDirection: true
            ),
            .item(duration: 0.3, directionHint: .up, invertOffsetDirection: true)
        )
    }

    func testNodeMaterializationPlannerTakesPreviousNodeOnceAndEvictsDuplicateTarget() {
        var planner = AetherListNodeMaterializationPlanner(
            previousNodeByIndex: [3: "old"],
            currentNodeByIndex: [1: "duplicate", 3: "old"]
        )

        let command = planner.takePreviousNode(previousIndex: 3, targetIndex: 1)
        XCTAssertEqual(command, AetherListNodeMaterializationCommand(
            nodeId: "old",
            previousIndex: 3,
            targetIndex: 1,
            duplicateTargetNodeId: "duplicate"
        ))
        XCTAssertEqual(planner.currentNodeId(at: 1), "old")
        XCTAssertNil(planner.currentNodeId(at: 3))
        XCTAssertNil(planner.takePreviousNode(previousIndex: 3, targetIndex: 2))
    }

    func testNodeMaterializationPlannerDoesNotEvictWhenPreviousNodeAlreadyOwnsTarget() {
        var planner = AetherListNodeMaterializationPlanner(
            previousNodeByIndex: [1: "same"],
            currentNodeByIndex: [1: "same"]
        )

        let command = planner.takePreviousNode(previousIndex: 1, targetIndex: 1)
        XCTAssertEqual(command, AetherListNodeMaterializationCommand(
            nodeId: "same",
            previousIndex: 1,
            targetIndex: 1,
            duplicateTargetNodeId: nil
        ))
        XCTAssertEqual(planner.currentNodeId(at: 1), "same")
        XCTAssertNil(planner.takePreviousNode(previousIndex: -1, targetIndex: 1))
        XCTAssertNil(planner.takePreviousNode(previousIndex: 1, targetIndex: -1))
    }

    func testUpdateMaterializationCommandsCanRunAgainstNonUIKitExecutor() {
        var planner = AetherListNodeMaterializationPlanner(
            previousNodeByIndex: [3: "old"],
            currentNodeByIndex: [1: "duplicate", 2: "current2"]
        )
        let descriptors = [
            AetherListUpdateMaterializationDescriptor(
                sourceIndex: 0,
                index: 1,
                previousIndex: 3,
                itemId: "u1",
                estimatedHeight: 51
            ),
            AetherListUpdateMaterializationDescriptor(
                sourceIndex: 1,
                index: 2,
                previousIndex: 99,
                itemId: "u2",
                estimatedHeight: 62
            ),
            AetherListUpdateMaterializationDescriptor(
                sourceIndex: 2,
                index: 4,
                previousIndex: 0,
                itemId: "invalid",
                estimatedHeight: 70
            ),
            AetherListUpdateMaterializationDescriptor(
                sourceIndex: 3,
                index: 0,
                previousIndex: 99,
                itemId: "u0",
                estimatedHeight: 40
            )
        ]

        let commands = AetherListUpdateMaterializationCommandPlanner.commands(
            descriptors: descriptors,
            itemCount: 4,
            materializationPlanner: &planner
        )
        let executor = RecordingUpdateMaterializationExecutor<String, String>()
        commands.forEach { executor.execute($0) }

        XCTAssertEqual(executor.commands, [
            .materialize(
                index: 1,
                sourceIndex: 0,
                itemId: "u1",
                nodeSource: .previous(AetherListNodeMaterializationCommand(
                    nodeId: "old",
                    previousIndex: 3,
                    targetIndex: 1,
                    duplicateTargetNodeId: "duplicate"
                ))
            ),
            .materialize(
                index: 2,
                sourceIndex: 1,
                itemId: "u2",
                nodeSource: .current("current2")
            ),
            .setEstimatedHeight(
                index: 0,
                sourceIndex: 3,
                itemId: "u0",
                height: 40
            )
        ])
        XCTAssertEqual(planner.currentNodeId(at: 1), "old")
        XCTAssertEqual(planner.currentNodeId(at: 2), "current2")
    }

    func testVisibleNodeMaterializationCommandsCanRunAgainstNonUIKitExecutor() {
        var planner = AetherListNodeMaterializationPlanner(
            previousNodeByIndex: [4: "old4"],
            currentNodeByIndex: [0: "current0", 2: "current2"]
        )

        let commands = AetherListVisibleNodeMaterializationCommandPlanner.commands(
            visibleRange: 0..<4,
            insertPreviousIndexByTargetIndex: [1: 4, 2: 8],
            materializationPlanner: &planner
        )
        let executor = RecordingVisibleNodeMaterializationExecutor<String>()
        commands.forEach { executor.execute($0) }

        XCTAssertEqual(executor.commands, [
            .mount(
                index: 1,
                source: .previous(AetherListNodeMaterializationCommand(
                    nodeId: "old4",
                    previousIndex: 4,
                    targetIndex: 1,
                    duplicateTargetNodeId: nil
                ))
            ),
            .mount(index: 3, source: .reusableOrCreated)
        ])
        XCTAssertEqual(planner.currentNodeId(at: 0), "current0")
        XCTAssertEqual(planner.currentNodeId(at: 1), "old4")
        XCTAssertEqual(planner.currentNodeId(at: 2), "current2")
    }

    func testStickyHeaderCommandsCanRunAgainstNonUIKitExecutor() {
        let descriptors = [
            AetherListStickyHeaderDescriptor(
                index: 0,
                affinity: .top,
                naturalY: 0,
                height: 20,
                nodeId: "top0"
            ),
            AetherListStickyHeaderDescriptor(
                index: 2,
                affinity: .top,
                naturalY: 90,
                height: 20,
                nodeId: "top2"
            ),
            AetherListStickyHeaderDescriptor(
                index: 3,
                affinity: .bottom,
                naturalY: 160,
                height: 30,
                nodeId: nil
            )
        ]

        let commands = AetherListStickyHeaderCommandPlanner.commands(
            descriptors: descriptors,
            viewportTop: 75,
            viewportBottom: 100,
            boundsWidth: 320,
            displayScale: 1
        )
        let executor = RecordingStickyHeaderExecutor<String>()
        commands.forEach { executor.execute($0) }

        XCTAssertEqual(executor.commands, [
            .ensureNode(index: 3),
            .applyLayout(
                nodeId: "top0",
                index: 0,
                frame: CGRect(x: 0, y: 70, width: 320, height: 20),
                state: AetherListStickyHeaderState(
                    affinity: .top,
                    isPinned: false,
                    isFloating: true,
                    isFlashing: true
                ),
                zPosition: 1000,
                bringToFront: true
            ),
            .applyLayout(
                nodeId: "top2",
                index: 2,
                frame: CGRect(x: 0, y: 90, width: 320, height: 20),
                state: .none,
                zPosition: 0,
                bringToFront: false
            )
        ])
        XCTAssertEqual(
            AetherListStickyHeaderCommandPlanner.pinnedIndices(
                descriptors: descriptors,
                viewportTop: 75,
                viewportBottom: 100
            ),
            [0, 3]
        )
    }

    func testBottomStickyHeaderCommandPinsToViewportBottom() {
        let descriptors = [
            AetherListStickyHeaderDescriptor(
                index: 1,
                affinity: .bottom,
                naturalY: 300,
                height: 40,
                nodeId: "bottom"
            )
        ]
        let commands = AetherListStickyHeaderCommandPlanner.commands(
            descriptors: descriptors,
            viewportTop: 0,
            viewportBottom: 100,
            boundsWidth: 320,
            displayScale: 1
        )

        XCTAssertEqual(commands, [
            .applyLayout(
                nodeId: "bottom",
                index: 1,
                frame: CGRect(x: 0, y: 60, width: 320, height: 40),
                state: AetherListStickyHeaderState(
                    affinity: .bottom,
                    isPinned: true,
                    isFloating: true,
                    isFlashing: true
                ),
                zPosition: 1000,
                bringToFront: true
            )
        ])
    }

    func testVirtualizationCommandsCanRunAgainstNonUIKitExecutor() {
        let loadedNodes = [
            AetherListVirtualizationLoadedNode(nodeId: "old0", index: 0, isProtected: false),
            AetherListVirtualizationLoadedNode(nodeId: "drag1", index: 1, isProtected: true),
            AetherListVirtualizationLoadedNode(nodeId: "visible2", index: 2, isProtected: false),
            AetherListVirtualizationLoadedNode(nodeId: "pinned6", index: 6, isProtected: false),
            AetherListVirtualizationLoadedNode(nodeId: "unindexed", index: nil, isProtected: false)
        ]
        let commands = AetherListVirtualizationCommandPlanner.commands(
            visibleRange: 2..<5,
            pinnedIndices: [6],
            loadedNodes: loadedNodes,
            itemOffsets: [0, 10, 20, 30, 40, 50, 60],
            itemHeights: [10, 10, 10, 10, 10, 10, 10],
            boundsWidth: 320,
            displayScale: 1
        )
        let executor = RecordingVirtualizationExecutor<String>()
        commands.forEach { executor.execute($0) }

        XCTAssertEqual(executor.commands, [
            .recycle(nodeId: "old0", index: 0),
            .mount(index: 3),
            .mount(index: 4),
            .setFrame(
                nodeId: "drag1",
                index: 1,
                frame: CGRect(x: 0, y: 10, width: 320, height: 10)
            ),
            .setFrame(
                nodeId: "visible2",
                index: 2,
                frame: CGRect(x: 0, y: 20, width: 320, height: 10)
            ),
            .setFrame(
                nodeId: "pinned6",
                index: 6,
                frame: CGRect(x: 0, y: 60, width: 320, height: 10)
            )
        ])
    }

    func testAsyncLayoutCommandsCanRunAgainstNonUIKitExecutor() {
        let descriptors = [
            AetherListAsyncLayoutItemDescriptor(
                index: 0,
                itemId: "cached0",
                reuseIdentifier: "text",
                hasPreparedLayout: true,
                hasPendingLayoutTask: false,
                isKnownSynchronous: false
            ),
            AetherListAsyncLayoutItemDescriptor(
                index: 1,
                itemId: "stalePending1",
                reuseIdentifier: "image",
                hasPreparedLayout: false,
                hasPendingLayoutTask: true,
                isKnownSynchronous: false
            ),
            AetherListAsyncLayoutItemDescriptor(
                index: 2,
                itemId: "ready2",
                reuseIdentifier: "text",
                hasPreparedLayout: false,
                hasPendingLayoutTask: false,
                isKnownSynchronous: false
            ),
            AetherListAsyncLayoutItemDescriptor(
                index: 3,
                itemId: "pending3",
                reuseIdentifier: "image",
                hasPreparedLayout: false,
                hasPendingLayoutTask: true,
                isKnownSynchronous: false
            ),
            AetherListAsyncLayoutItemDescriptor(
                index: 4,
                itemId: "sync4",
                reuseIdentifier: "sync-row",
                hasPreparedLayout: false,
                hasPendingLayoutTask: false,
                isKnownSynchronous: true
            ),
            AetherListAsyncLayoutItemDescriptor(
                index: 6,
                itemId: "stalePending6",
                reuseIdentifier: "image",
                hasPreparedLayout: false,
                hasPendingLayoutTask: true,
                isKnownSynchronous: false
            )
        ]
        let commands = AetherListAsyncLayoutCommandPlanner.commands(
            prefetchRange: 2..<5,
            itemDescriptors: descriptors
        )
        let executor = RecordingAsyncLayoutExecutor<String>()
        commands.forEach { executor.execute($0) }

        XCTAssertEqual(executor.commands, [
            .cancel(itemId: "stalePending1"),
            .cancel(itemId: "stalePending6"),
            .prepare(index: 2, itemId: "ready2")
        ])
    }

    func testVisibilityLifecycleCommandsCanRunAgainstNonUIKitExecutor() {
        let descriptors = [
            AetherListVisibilityNodeDescriptor(
                nodeId: "old0",
                index: 0,
                frame: CGRect(x: 0, y: -80, width: 320, height: 40),
                isAccessibilityVisible: true
            ),
            AetherListVisibilityNodeDescriptor(
                nodeId: "hidden1",
                index: 1,
                frame: CGRect(x: 0, y: 0, width: 320, height: 20),
                isAccessibilityVisible: false
            ),
            AetherListVisibilityNodeDescriptor(
                nodeId: "visible2",
                index: 2,
                frame: CGRect(x: 0, y: 20, width: 320, height: 40),
                isAccessibilityVisible: true
            ),
            AetherListVisibilityNodeDescriptor(
                nodeId: "later4",
                index: 4,
                frame: CGRect(x: 0, y: 120, width: 320, height: 40),
                isAccessibilityVisible: true
            ),
            AetherListVisibilityNodeDescriptor(
                nodeId: "unindexed",
                index: nil,
                frame: CGRect(x: 0, y: 10, width: 320, height: 10),
                isAccessibilityVisible: true
            )
        ]
        let snapshot = AetherListVisibilityLifecycleCommandPlanner.snapshot(
            nodeDescriptors: descriptors,
            viewportTop: 0,
            viewportHeight: 100
        )
        let commands = AetherListVisibilityLifecycleCommandPlanner.commands(
            snapshot: snapshot,
            notifyDisplayedRange: true
        )
        let executor = RecordingVisibilityLifecycleExecutor<String>()
        commands.forEach { executor.execute($0) }

        XCTAssertEqual(snapshot.displayedRange.loadedRange, 0..<5)
        XCTAssertEqual(snapshot.displayedRange.visibleRange, 1..<3)
        XCTAssertEqual(snapshot.displayedRange.visibleItemRange, AetherListVisibleItemRange(
            firstIndex: 1,
            firstIndexFullyVisible: true,
            lastIndex: 2
        ))
        XCTAssertEqual(snapshot.accessibilityNodeIds, ["old0", "visible2", "later4", "unindexed"])
        XCTAssertEqual(executor.commands, [
            .recordVisibleViews(count: 5),
            .setAccessibilityOrder(nodeIds: ["old0", "visible2", "later4", "unindexed"]),
            .notifyDisplayedRange(snapshot.displayedRange)
        ])
    }

    func testContentMetricsIncludeVirtualInsets() {
        let metrics = AetherListContentMetricsPlanner.metrics(
            itemHeights: [10, 20, 30],
            itemOffsetInsets: UIEdgeInsets(top: 6, left: 0, bottom: 7, right: 0),
            virtualContentInsets: AetherListVirtualContentInsets(top: 100, bottom: 50)
        )

        XCTAssertEqual(metrics.effectiveOffsetInsets.top, 106)
        XCTAssertEqual(metrics.effectiveOffsetInsets.bottom, 57)
        XCTAssertEqual(metrics.itemOffsets, [106, 116, 136])
        XCTAssertEqual(metrics.totalContentHeight, 223)
        XCTAssertEqual(AetherListContentMetricsPlanner.topDelta(
            from: UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0),
            to: UIEdgeInsets(top: 35, left: 0, bottom: 0, right: 0)
        ), 25)
    }

    func testEffectiveInsetsPlannerKeepsBottomAnchorWhenBottomInsetChanges() {
        let plan = AetherListEffectiveInsetsPlanner.plan(
            baseInsets: UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0),
            keyboardBottomInset: 40,
            explicitScrollIndicatorInsets: nil,
            stackFromBottom: false,
            totalContentHeight: 500,
            viewportHeight: 100,
            contentSizeHeight: 500,
            currentContentInset: UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0),
            currentContentOffset: CGPoint(x: 2, y: 416),
            isTrackingOrDragging: false,
            bottomAnchorTolerance: 8
        )

        XCTAssertEqual(plan.contentInset.bottom, 60)
        XCTAssertEqual(plan.scrollIndicatorInsets.bottom, 60)
        XCTAssertEqual(plan.contentOffset, CGPoint(x: 2, y: 460))
    }

    func testEffectiveInsetsPlannerCompensatesTopInsetWhenNotDragging() {
        let plan = AetherListEffectiveInsetsPlanner.plan(
            baseInsets: UIEdgeInsets(top: 35, left: 0, bottom: 20, right: 0),
            keyboardBottomInset: 0,
            explicitScrollIndicatorInsets: nil,
            stackFromBottom: false,
            totalContentHeight: 500,
            viewportHeight: 100,
            contentSizeHeight: 500,
            currentContentInset: UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0),
            currentContentOffset: CGPoint(x: 2, y: 100),
            isTrackingOrDragging: false,
            bottomAnchorTolerance: 8
        )

        XCTAssertEqual(plan.contentOffset, CGPoint(x: 2, y: 75))
    }

    func testEffectiveInsetsPlannerDoesNotMoveMiddleOffsetForBottomInsetOnlyChange() {
        let plan = AetherListEffectiveInsetsPlanner.plan(
            baseInsets: UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0),
            keyboardBottomInset: 40,
            explicitScrollIndicatorInsets: nil,
            stackFromBottom: false,
            totalContentHeight: 500,
            viewportHeight: 100,
            contentSizeHeight: 500,
            currentContentInset: UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0),
            currentContentOffset: CGPoint(x: 2, y: 100),
            isTrackingOrDragging: false,
            bottomAnchorTolerance: 8
        )

        XCTAssertNil(plan.contentOffset)
    }

    func testEffectiveInsetsPlannerPadsShortStackFromBottomContent() {
        let plan = AetherListEffectiveInsetsPlanner.plan(
            baseInsets: .zero,
            keyboardBottomInset: 20,
            explicitScrollIndicatorInsets: nil,
            stackFromBottom: true,
            totalContentHeight: 40,
            viewportHeight: 100,
            contentSizeHeight: 40,
            currentContentInset: .zero,
            currentContentOffset: .zero,
            isTrackingOrDragging: false,
            bottomAnchorTolerance: 8
        )

        XCTAssertEqual(plan.contentInset.top, 40)
        XCTAssertEqual(plan.contentInset.bottom, 20)
        XCTAssertEqual(plan.contentOffset, CGPoint(x: 0, y: -40))
    }

    func testBoundaryTriggerPlannerUsesDistanceAndItemThresholds() {
        let snapshot = AetherListBoundaryTriggerSnapshot(
            itemCount: 100,
            displayedRange: AetherListDisplayedItemRange(
                loadedRange: 0..<20,
                visibleRange: 4..<8
            ),
            visibleContentOffset: 120,
            visibleBottomContentOffset: 900,
            isUserInitiated: true
        )
        let triggers = AetherListBoundaryTriggerPlanner.triggers(
            snapshot: snapshot,
            configuration: AetherListBoundaryTriggerConfiguration(
                topDistance: 100,
                bottomDistance: 100,
                topItemThreshold: 2,
                bottomItemThreshold: 5,
                triggersDuringProgrammaticScroll: false
            )
        )

        XCTAssertEqual(triggers, [
            AetherListBoundaryTrigger(edge: .top, reasons: [.itemThreshold])
        ])
    }

    func testBoundaryTriggerPlannerHonorsProgrammaticScrollSetting() {
        let snapshot = AetherListBoundaryTriggerSnapshot(
            itemCount: 10,
            displayedRange: AetherListDisplayedItemRange(
                loadedRange: 0..<5,
                visibleRange: 0..<2
            ),
            visibleContentOffset: 0,
            visibleBottomContentOffset: 400,
            isUserInitiated: false
        )

        XCTAssertEqual(AetherListBoundaryTriggerPlanner.triggers(
            snapshot: snapshot,
            configuration: AetherListBoundaryTriggerConfiguration(
                topDistance: 20,
                triggersDuringProgrammaticScroll: false
            )
        ), [])
        XCTAssertEqual(AetherListBoundaryTriggerPlanner.triggers(
            snapshot: snapshot,
            configuration: AetherListBoundaryTriggerConfiguration(topDistance: 20)
        ), [
            AetherListBoundaryTrigger(edge: .top, reasons: [.distance])
        ])
    }

    func testModelMutationCommandsCanRunAgainstNonUIKitExecutor() {
        let firstInsert = AetherListModelMutationInsertDescriptor(
            sourceIndex: 0,
            requestedIndex: -5,
            itemId: "x",
            estimatedHeight: 5,
            previousIndex: 3,
            directionHint: .up,
            forceAnimateInsertion: true
        )
        let secondInsert = AetherListModelMutationInsertDescriptor(
            sourceIndex: 1,
            requestedIndex: 2,
            itemId: "y",
            estimatedHeight: 6,
            previousIndex: nil,
            directionHint: .down,
            forceAnimateInsertion: false
        )
        let plan = AetherListModelMutationCommandPlanner.plan(
            itemIds: ["a", "b", "c", "d"],
            itemHeights: [10, 20, 30, 40],
            deleteItems: [
                AetherListDeleteItem(index: 1, directionHint: .down, animation: .scale)
            ],
            moveItems: [
                AetherListMoveItem(fromIndex: 2, toIndex: 0)
            ],
            insertDescriptors: [secondInsert, firstInsert]
        )

        let executor = RecordingModelMutationExecutor<String>()
        plan.commands.forEach { executor.execute($0) }

        XCTAssertEqual(executor.commands, [
            .delete(index: 1, itemId: "b", animation: .scale, hint: .down),
            .move(fromIndex: 2, toIndex: 0),
            .insert(index: 0, descriptor: firstInsert),
            .insert(index: 2, descriptor: secondInsert)
        ])
        XCTAssertEqual(plan.itemIds, ["x", "d", "y", "a", "c"])
        XCTAssertEqual(plan.itemHeights, [5, 40, 6, 10, 30])
        XCTAssertEqual(plan.insertPreviousIndexByTargetIndex, [0: 3])
        XCTAssertEqual(plan.insertDirectionHintByTargetIndex, [0: .up, 2: .down])
        XCTAssertEqual(plan.forceAnimateInsertionIndices, [0])
    }

    func testModelMutationPlannerSkipsInvalidOperations() {
        let plan = AetherListModelMutationCommandPlanner.plan(
            itemIds: ["a", "b"],
            itemHeights: [10, 20],
            deleteItems: [AetherListDeleteItem(index: 4)],
            moveItems: [AetherListMoveItem(fromIndex: -1, toIndex: 0)],
            insertDescriptors: []
        )

        XCTAssertEqual(plan.commands, [])
        XCTAssertEqual(plan.itemIds, ["a", "b"])
        XCTAssertEqual(plan.itemHeights, [10, 20])
    }

    func testFrameReplayCommandsCanRunAgainstNonUIKitExecutor() {
        let replayPlan = AetherListNodeReplayPlan.make(
            options: [.animateInsertions, .animateAlpha],
            hasForcedInsertionAnimation: false,
            hasParticleDissolveRemoval: false,
            baseDuration: 0.3,
            particleDissolveDuration: 0.72,
            reduceMotionEnabled: false
        )
        let commands = AetherListFrameReplayCommandPlanner.commands(
            nodeIdsInDisplayOrder: ["existing", "inserted"],
            indexByNodeId: ["existing": 0, "inserted": 1],
            targetFrameByNodeId: [
                "existing": CGRect(x: 0, y: 10, width: 320, height: 44),
                "inserted": CGRect(x: 0, y: 54, width: 320, height: 30)
            ],
            previousFrameByNodeId: [
                "existing": CGRect(x: 0, y: 0, width: 320, height: 44)
            ],
            insertedNodeIds: ["inserted"],
            removals: [
                AetherListFrameReplayRemoval(nodeId: "removed", animation: .scale, hint: .down)
            ],
            replayPlan: replayPlan,
            forceItemAnimationIndices: [],
            insertionDirectionHintByIndex: [:],
            requestItemInsertionAnimations: false,
            invertOffsetDirection: false
        )

        let executor = RecordingFrameReplayExecutor<String>()
        commands.forEach { executor.execute($0) }

        XCTAssertEqual(executor.commands, [
            .animateFrame(
                nodeId: "existing",
                from: CGRect(x: 0, y: 0, width: 320, height: 44),
                to: CGRect(x: 0, y: 10, width: 320, height: 44),
                duration: 0.3,
                curve: .standard
            ),
            .insert(
                nodeId: "inserted",
                frame: CGRect(x: 0, y: 54, width: 320, height: 30),
                animation: .alphaFade(duration: 0.1)
            ),
            .remove(nodeId: "removed", animation: .fade, hint: .down)
        ])
    }

    func testFrameReplayCommandsUseImmediateRemovalWhenAnimationsAreDisabled() {
        let replayPlan = AetherListNodeReplayPlan.make(
            options: [.animateInsertions],
            hasForcedInsertionAnimation: true,
            hasParticleDissolveRemoval: false,
            baseDuration: 0.3,
            particleDissolveDuration: 0.72,
            reduceMotionEnabled: true
        )
        let commands = AetherListFrameReplayCommandPlanner.commands(
            nodeIdsInDisplayOrder: ["node"],
            indexByNodeId: ["node": 0],
            targetFrameByNodeId: ["node": CGRect(x: 0, y: 0, width: 320, height: 44)],
            previousFrameByNodeId: ["node": CGRect(x: 0, y: 20, width: 320, height: 44)],
            insertedNodeIds: [],
            removals: [
                AetherListFrameReplayRemoval(nodeId: "removed", animation: .fade, hint: nil)
            ],
            replayPlan: replayPlan,
            forceItemAnimationIndices: [],
            insertionDirectionHintByIndex: [:],
            requestItemInsertionAnimations: false,
            invertOffsetDirection: false
        )

        XCTAssertEqual(commands, [
            .setFrame(nodeId: "node", frame: CGRect(x: 0, y: 0, width: 320, height: 44)),
            .remove(nodeId: "removed", animation: nil, hint: nil)
        ])
    }

    func testSizeAndInsetsCommandCanRunAgainstNonUIKitExecutor() throws {
        let update = AetherListUpdateSizeAndInsets(
            size: CGSize(width: 375, height: 667),
            insets: UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0),
            headerInsets: UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0),
            scrollIndicatorInsets: UIEdgeInsets(top: 2, left: 0, bottom: 8, right: 0),
            itemOffsetInsets: UIEdgeInsets(top: 6, left: 0, bottom: 7, right: 0),
            virtualContentInsets: AetherListVirtualContentInsets(top: 9, bottom: 11),
            duration: 0.25,
            curve: .easeInOut
        )
        let command = AetherListSizeAndInsetsCommandPlanner.command(
            currentFrame: CGRect(x: 8, y: 12, width: 320, height: 480),
            currentBoundsSize: CGSize(width: 320, height: 480),
            safeAreaInsets: UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 8),
            currentLayoutParams: AetherListItemLayoutParams(width: 320, availableHeight: 480),
            options: [],
            update: update
        )

        let executor = RecordingSizeAndInsetsExecutor()
        executor.execute(try XCTUnwrap(command))

        XCTAssertEqual(executor.commands, [
            .update(AetherListSizeAndInsetsUpdateCommand(
                targetFrame: CGRect(x: 8, y: 12, width: 375, height: 667),
                updatedLayoutParams: AetherListItemLayoutParams(
                    width: 375,
                    leftInset: 12,
                    rightInset: 8,
                    availableHeight: 667
                ),
                headerInsets: UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0),
                scrollIndicatorInsets: UIEdgeInsets(top: 2, left: 0, bottom: 8, right: 0),
                itemOffsetInsets: UIEdgeInsets(top: 6, left: 0, bottom: 7, right: 0),
                virtualContentInsets: AetherListVirtualContentInsets(top: 9, bottom: 11),
                insets: UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0),
                transition: .animated(duration: 0.25, curve: .easeInOut),
                prefersCustomTransition: false
            ))
        ])
    }

    func testSizeAndInsetsPlannerEmitsForceRelayoutCommand() {
        let params = AetherListItemLayoutParams(width: 320, availableHeight: 480)
        let command = AetherListSizeAndInsetsCommandPlanner.command(
            currentFrame: CGRect(x: 0, y: 0, width: 320, height: 480),
            currentBoundsSize: CGSize(width: 320, height: 480),
            safeAreaInsets: .zero,
            currentLayoutParams: params,
            options: [.forceUpdate],
            update: nil
        )

        XCTAssertEqual(command, .forceRelayout(params: params))
    }

    func testScrollAnchoringCommandCanRunAgainstNonUIKitExecutor() throws {
        let state = AetherListIntermediateState(
            stableIds: [0, 1, 2],
            heights: [40, 50, 60]
        )
        let command = AetherListScrollAnchoringCommandPlanner.command(
            itemCount: 3,
            scrollToItem: AetherListScrollToItem(index: 1, position: .top(offset: 0), animated: true),
            resolvedScrollToOffsetY: 40,
            additionalScrollDistance: 12,
            additionalDistanceTransition: .animated(duration: 0.2, curve: .linear),
            stationaryAnchor: nil,
            postIntermediateState: state,
            currentContentOffset: CGPoint(x: 3, y: 5),
            stackFromBottom: true,
            wasNearBottom: true,
            animate: false,
            animateTopItemPosition: false
        )

        let executor = RecordingScrollAnchoringExecutor()
        executor.execute(try XCTUnwrap(command))

        XCTAssertEqual(executor.commands, [
            .setContentOffset(CGPoint(x: 3, y: 52), animated: true)
        ])
    }

    func testScrollAnchoringPlannerPreservesStationaryAnchor() {
        let state = AetherListIntermediateState(
            stableIds: [9, 1, 2],
            heights: [30, 50, 60]
        )
        let command = AetherListScrollAnchoringCommandPlanner.command(
            itemCount: 3,
            scrollToItem: nil,
            resolvedScrollToOffsetY: nil,
            additionalScrollDistance: 0,
            additionalDistanceTransition: .immediate,
            stationaryAnchor: AetherListIntermediateAnchor(stableId: 1, index: 0, offset: 0),
            postIntermediateState: state,
            currentContentOffset: CGPoint(x: 2, y: 100),
            stackFromBottom: true,
            wasNearBottom: true,
            animate: true,
            animateTopItemPosition: true
        )

        XCTAssertEqual(command, .setContentOffset(CGPoint(x: 2, y: 130), animated: true))
    }

    func testScrollAnchoringPlannerKeepsBottomWhenStationaryAnchorIsLost() {
        let state = AetherListIntermediateState(
            stableIds: [0, 2],
            heights: [40, 60]
        )
        let command = AetherListScrollAnchoringCommandPlanner.command(
            itemCount: 2,
            scrollToItem: nil,
            resolvedScrollToOffsetY: nil,
            additionalScrollDistance: 0,
            additionalDistanceTransition: .immediate,
            stationaryAnchor: AetherListIntermediateAnchor(stableId: 1, index: 1, offset: 40),
            postIntermediateState: state,
            currentContentOffset: .zero,
            stackFromBottom: true,
            wasNearBottom: true,
            animate: false,
            animateTopItemPosition: false
        )

        XCTAssertEqual(command, .applyEffectiveInsetsAndScrollToBottom(animated: false))
    }

    func testIntermediateStatePreservesStableAnchorAcrossInsertAbove() throws {
        let state = AetherListIntermediateState(
            stableIds: [0, 1, 2],
            heights: [50, 50, 50]
        )
        let anchor = try XCTUnwrap(state.stationaryAnchor(in: (1, 1)))
        let after = state.applying(
            insertItems: [
                AetherListIntermediateInsertItem(
                    index: 0,
                    item: AetherListIntermediateItem(stableId: 99, height: 30)
                )
            ]
        )

        XCTAssertEqual(anchor.stableId, 1)
        XCTAssertEqual(after.index(of: 1), 2)
        XCTAssertEqual(after.offsetDelta(preserving: anchor), 30)
    }

    func testIntermediatePlannerReturnsBeforeAndAfterState() throws {
        let state = AetherListIntermediateState(
            stableIds: [0, 1, 2],
            heights: [20, 30, 40]
        )
        let plan = AetherListTransactionPlanner.plan(
            state: state,
            deleteIndices: [0],
            insertItems: [
                AetherListIntermediateInsertItem(
                    index: 1,
                    item: AetherListIntermediateItem(stableId: 3, height: 10)
                )
            ],
            moveIndices: [(fromIndex: 1, toIndex: 0)],
            updateItems: [
                AetherListIntermediateUpdateItem(
                    index: 1,
                    previousIndex: 1,
                    item: AetherListIntermediateItem(stableId: 4, height: 60)
                )
            ]
        )

        XCTAssertEqual(plan.beforeState, state)
        XCTAssertEqual(plan.afterState?.items.map(\.stableId), [2, 4, 1])
        XCTAssertEqual(plan.afterState?.itemOffsets, [0, 40, 100])
    }

    @MainActor
    func testScrollerKeepsNativePanGestureAndHostedBackingView() throws {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.layoutIfNeeded()

        let scroller = try XCTUnwrap(listView.scroller as? AetherListScroller)
        XCTAssertTrue(scroller.subviews.contains(where: { $0 === scroller.backingView }))
        XCTAssertFalse(listView.subviews.contains(where: { $0 === scroller.backingView }))
        XCTAssertTrue(scroller.gestureRecognizers?.contains(where: { $0 === scroller.panGestureRecognizer }) ?? false)
        XCTAssertTrue(scroller.bounces)
        XCTAssertTrue(scroller.alwaysBounceVertical)
    }

    func testOverscrollDistancesUseScrollableBounds() {
        let none = AetherListFrameMetrics.overscrollDistances(
            contentOffsetY: 0,
            contentSizeHeight: 44,
            viewportHeight: 100,
            contentInset: .zero
        )
        XCTAssertEqual(none.top, 0)
        XCTAssertEqual(none.bottom, 0)

        let top = AetherListFrameMetrics.overscrollDistances(
            contentOffsetY: -30,
            contentSizeHeight: 44,
            viewportHeight: 100,
            contentInset: .zero
        )
        XCTAssertEqual(top.top, 30)
        XCTAssertEqual(top.bottom, 0)
    }

    func testCustomScrollIndicatorFrameHidesWhenNotScrollableAndCanFollowOverscroll() throws {
        XCTAssertNil(AetherListFrameMetrics.verticalScrollIndicatorFrame(
            boundsWidth: 320,
            viewportHeight: 100,
            contentSizeHeight: 44,
            contentInset: .zero,
            scrollIndicatorInsets: nil,
            contentOffsetY: 0,
            followsOverscroll: false
        ))

        let pinned = try XCTUnwrap(AetherListFrameMetrics.verticalScrollIndicatorFrame(
            boundsWidth: 320,
            viewportHeight: 100,
            contentSizeHeight: 500,
            contentInset: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
            scrollIndicatorInsets: UIEdgeInsets(top: 10, left: 0, bottom: 15, right: 0),
            contentOffsetY: -70,
            followsOverscroll: false
        ))
        let following = try XCTUnwrap(AetherListFrameMetrics.verticalScrollIndicatorFrame(
            boundsWidth: 320,
            viewportHeight: 100,
            contentSizeHeight: 500,
            contentInset: UIEdgeInsets(top: 20, left: 0, bottom: 30, right: 0),
            scrollIndicatorInsets: UIEdgeInsets(top: 10, left: 0, bottom: 15, right: 0),
            contentOffsetY: -70,
            followsOverscroll: true
        ))

        XCTAssertEqual(pinned.minY, 10, accuracy: 0.5)
        XCTAssertLessThan(following.minY, pinned.minY)
        XCTAssertEqual(pinned.height, following.height, accuracy: 0.5)
    }

    @MainActor
    func testShortContentDoesNotReportBottomOverscrollAtRest() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        var bottomOverscroll: CGFloat = -1
        let bottomBackgroundView = UIView()
        listView.bottomOverscrollChanged = { bottomOverscroll = $0 }
        listView.bottomOverscrollBackgroundView = bottomBackgroundView
        listView.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: 0, item: TestItem(id: 1, height: 44))],
            options: [.synchronous]
        )
        listView.scrollViewDidScroll(listView.scroller)

        XCTAssertEqual(bottomOverscroll, 0, accuracy: 0.5)
        XCTAssertEqual(bottomBackgroundView.frame.height, 0, accuracy: 0.5)
    }

    @MainActor
    func testVirtualContentInsetsPreserveVisibleOffset() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        let items: [AetherListItem] = (0..<5).map { TestItem(id: $0, height: 50) }
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
        listView.scroller.setContentOffset(CGPoint(x: 0, y: 50), animated: false)
        listView.scrollViewDidScroll(listView.scroller)

        listView.virtualContentInsets = AetherListVirtualContentInsets(top: 120, bottom: 30)

        XCTAssertEqual(listView.scroller.contentSize.height, 400, accuracy: 0.5)
        XCTAssertEqual(listView.scroller.contentOffset.y, 170, accuracy: 0.5)
        XCTAssertEqual(listView.state.virtualContentInsets, AetherListVirtualContentInsets(top: 120, bottom: 30))
        XCTAssertEqual(listView.state.totalContentHeight, 400, accuracy: 0.5)
    }

    @MainActor
    func testBottomInsetChangeKeepsVisibleBottomAnchored() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        let items: [AetherListItem] = (0..<5).map { TestItem(id: $0, height: 50) }
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
        listView.scrollToBottom(animated: false)
        XCTAssertEqual(listView.scroller.contentOffset.y, 150, accuracy: 0.5)

        listView.updateInsets(UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0), transition: .immediate)

        XCTAssertEqual(listView.scroller.contentInset.bottom, 80, accuracy: 0.5)
        XCTAssertEqual(listView.scroller.contentOffset.y, 230, accuracy: 0.5)
    }

    @MainActor
    func testBoundaryTriggerCallbackDeduplicatesUntilLeavingEdge() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        var contexts: [AetherListBoundaryTriggerContext] = []
        listView.boundaryReached = { contexts.append($0) }
        listView.boundaryTriggerConfiguration = AetherListBoundaryTriggerConfiguration(
            topDistance: 40,
            topItemThreshold: 0
        )
        let items: [AetherListItem] = (0..<8).map { TestItem(id: $0, height: 50) }
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )

        XCTAssertEqual(contexts.map(\.edge), [.top])
        XCTAssertEqual(contexts[0].reasons, [.distance, .itemThreshold])

        listView.scrollViewDidScroll(listView.scroller)
        XCTAssertEqual(contexts.count, 1)

        listView.scroller.setContentOffset(CGPoint(x: 0, y: 120), animated: false)
        listView.scrollViewDidScroll(listView.scroller)
        XCTAssertEqual(contexts.count, 1)

        listView.scroller.setContentOffset(.zero, animated: false)
        listView.scrollViewDidScroll(listView.scroller)
        XCTAssertEqual(contexts.map(\.edge), [.top, .top])
    }

    @MainActor
    func testBoundaryTriggerCallbackCanRequireUserInitiatedScroll() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        var contexts: [AetherListBoundaryTriggerContext] = []
        listView.boundaryReached = { contexts.append($0) }
        listView.boundaryTriggerConfiguration = AetherListBoundaryTriggerConfiguration(
            topDistance: 40,
            triggersDuringProgrammaticScroll: false
        )
        let items: [AetherListItem] = (0..<4).map { TestItem(id: $0, height: 50) }
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )

        XCTAssertTrue(contexts.isEmpty)
    }

    @MainActor
    func testListGestureHitTestingRespectsNestedControlsAndExternalGate() throws {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        listView.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: 0, item: ControlHitTestItem(id: 1))],
            options: [.synchronous]
        )

        let node = try XCTUnwrap(listView.nodeForItem(at: 0))
        node.layoutIfNeeded()

        XCTAssertNil(listView.itemNodeForListGesture(at: CGPoint(x: 20, y: 20), gesture: .tap))
        XCTAssertTrue(listView.itemNodeForListGesture(at: CGPoint(x: 120, y: 20), gesture: .tap) === node)

        listView.allowsReorder = true
        XCTAssertNil(listView.itemNodeForListGesture(at: CGPoint(x: 20, y: 20), gesture: .reorder))
        XCTAssertTrue(listView.itemNodeForListGesture(at: CGPoint(x: 120, y: 20), gesture: .reorder) === node)

        listView.itemGestureShouldBegin = { gesture, index, _, pointInNode in
            return gesture == .tap && index == 0 && pointInNode.x > 160
        }
        XCTAssertNil(listView.itemNodeForListGesture(at: CGPoint(x: 120, y: 20), gesture: .tap))
        XCTAssertTrue(listView.itemNodeForListGesture(at: CGPoint(x: 200, y: 20), gesture: .tap) === node)
    }

    @MainActor
    func testAccessoryItemIsHostedAndUpdatedByNode() throws {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        listView.transaction(
            insertIndicesAndItems: [
                AetherListInsertItem(
                    index: 0,
                    item: TestItem(id: 1, height: 44, accessoryItem: BadgeAccessoryItem(id: "badge", text: "A"))
                )
            ],
            options: [.synchronous]
        )

        let node = try XCTUnwrap(listView.nodeForItem(at: 0))
        node.layoutIfNeeded()
        let label = try XCTUnwrap(node.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(label.text, "A")
        XCTAssertEqual(label.frame.width, 24, accuracy: 0.5)
        XCTAssertEqual(label.frame.maxX, node.bounds.maxX - 16, accuracy: 0.5)

        listView.transaction(
            updateIndicesAndItems: [
                AetherListUpdateItem(
                    index: 0,
                    previousIndex: 0,
                    item: TestItem(id: 1, height: 44, accessoryItem: BadgeAccessoryItem(id: "badge", text: "B"))
                )
            ],
            options: [.synchronous]
        )

        node.layoutIfNeeded()
        XCTAssertTrue(node.subviews.contains(where: { $0 === label }))
        XCTAssertEqual(label.text, "B")
    }

    @MainActor
    func testBottomAffinityHeaderPinsToBottomEdge() throws {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        let items: [AetherListItem] = [
            TestItem(id: 1, height: 300),
            TestItem(id: 2, height: 40, headerAffinity: .bottom),
            TestItem(id: 3, height: 100)
        ]
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )

        let headerNode = try XCTUnwrap(listView.nodeForItem(at: 1))
        XCTAssertEqual(headerNode.frame.minY, 60, accuracy: 0.5)
        XCTAssertEqual(headerNode.frame.height, 40, accuracy: 0.5)
    }

    @MainActor
    func testPushedTopHeaderKeepsStickyStateAndHitTestPriority() throws {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        let items: [AetherListItem] = [
            TestItem(id: 1, height: 20, headerAffinity: .top),
            TestItem(id: 2, height: 70),
            TestItem(id: 3, height: 20, headerAffinity: .top),
            TestItem(id: 4, height: 100)
        ]
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )

        listView.scroller.setContentOffset(CGPoint(x: 0, y: 75), animated: false)
        listView.scrollViewDidScroll(listView.scroller)

        let headerNode = try XCTUnwrap(listView.nodeForItem(at: 0))
        XCTAssertEqual(headerNode.frame.minY, 70, accuracy: 0.5)
        XCTAssertFalse(headerNode.stickyHeaderState.isPinned)
        XCTAssertTrue(headerNode.stickyHeaderState.isFloating)
        XCTAssertTrue(headerNode.stickyHeaderState.isFlashing)
        XCTAssertEqual(headerNode.stickyHeaderState.affinity, .top)
        XCTAssertEqual(headerNode.layer.zPosition, 1000, accuracy: 0.5)

        let hitNode = try XCTUnwrap(listView.itemNodeForListGesture(at: CGPoint(x: 10, y: 80), gesture: .tap))
        XCTAssertTrue(hitNode === headerNode)
    }

    @MainActor
    func testAsyncPreparedLayoutAppliesToVisibleNode() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        let item = AsyncPreparedItem(id: 10)
        listView.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: 0, item: item)],
            options: [.synchronous]
        )

        let expectation = expectation(description: "prepared layout applied")
        DispatchQueue.main.async {
            let node = listView.nodeForItem(at: 0)
            XCTAssertEqual(node?.frame.height ?? 0, 80, accuracy: 0.5)
            XCTAssertTrue(item.didApplyPreparedLayout)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    @MainActor
    func testVirtualizationAndReusePoolCounters() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.debugInfo = true
        listView.layoutIfNeeded()

        let items: [AetherListItem] = (0..<100).map { TestItem(id: $0, height: 50) }
        let inserts = items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) }
        listView.transaction(insertIndicesAndItems: inserts, options: [.synchronous])

        XCTAssertLessThanOrEqual(listView.state.visibleViewCount, 4)
        XCTAssertNotEqual(listView.state.visibleViewCount, 100)

        listView.scroller.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        listView.scrollViewDidScroll(listView.scroller)

        XCTAssertLessThanOrEqual(listView.state.visibleViewCount, 5)
        XCTAssertGreaterThan(listView.debugInstrumentation.counters.reusedViews, 0)
    }

    @MainActor
    func testStationaryRangeTracksStableItemWhenInsertShiftsIndex() throws {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        let items: [TestItem] = (0..<5).map { TestItem(id: $0, height: 50) }
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
        listView.scroller.setContentOffset(CGPoint(x: 0, y: 50), animated: false)
        listView.scrollViewDidScroll(listView.scroller)

        listView.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: 0, item: TestItem(id: 99, height: 30))],
            options: [.synchronous],
            stationaryItemRange: (1, 1)
        )

        let anchoredNode = try XCTUnwrap(listView.nodeForItem(at: 2))
        XCTAssertEqual((anchoredNode.item as? TestItem)?.id, 1)
        XCTAssertEqual(listView.scroller.contentOffset.y, 80, accuracy: 0.5)
    }

    @MainActor
    func testTransactionHandlesInvalidNegativeIndices() throws {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.layoutIfNeeded()

        listView.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: 0, item: TestItem(id: 1, height: 44))],
            options: [.synchronous]
        )
        listView.transaction(
            deleteIndices: [AetherListDeleteItem(index: -1)],
            moveIndices: [AetherListMoveItem(fromIndex: -1, toIndex: 0)],
            insertIndicesAndItems: [AetherListInsertItem(index: -5, item: TestItem(id: 2, height: 44))],
            updateIndicesAndItems: [AetherListUpdateItem(index: -1, previousIndex: -1, item: TestItem(id: 3, height: 44))],
            options: [.synchronous]
        )

        XCTAssertEqual(listView.itemCount, 2)
        let firstNode = try XCTUnwrap(listView.nodeForItem(at: 0))
        XCTAssertEqual((firstNode.item as? TestItem)?.id, 2)
    }

    @MainActor
    func testStackFromBottomKeepsBottomAnchorWhenAppending() {
        let listView = AetherListView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        listView.preloadPages = 0
        listView.stackFromBottom = true
        listView.layoutIfNeeded()

        let items: [AetherListItem] = (0..<3).map { TestItem(id: $0, height: 50) }
        listView.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
        listView.scrollToBottom(animated: false)
        XCTAssertEqual(listView.scroller.contentOffset.y, 50, accuracy: 0.5)

        listView.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: 3, item: TestItem(id: 3, height: 40))],
            options: [.synchronous]
        )
        XCTAssertEqual(listView.scroller.contentOffset.y, 90, accuracy: 0.5)
    }
}

private final class TestItem: AetherListItem {
    let id: Int
    let height: CGFloat
    let headerAffinityValue: AetherListHeaderAffinity
    let accessoryValue: Any?
    let headerAccessoryValue: Any?

    init(
        id: Int,
        height: CGFloat,
        headerAffinity: AetherListHeaderAffinity = .none,
        accessoryItem: Any? = nil,
        headerAccessoryItem: Any? = nil
    ) {
        self.id = id
        self.height = height
        self.headerAffinityValue = headerAffinity
        self.accessoryValue = accessoryItem
        self.headerAccessoryValue = headerAccessoryItem
    }

    var stableId: AnyHashable { id }
    var approximateHeight: CGFloat { height }
    var estimatedHeight: CGFloat { height }
    var headerAffinity: AetherListHeaderAffinity { headerAffinityValue }
    var isFloatingHeader: Bool { headerAffinityValue == .top }
    var accessoryItem: Any? { accessoryValue }
    var headerAccessoryItem: Any? { headerAccessoryValue }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        return (TestNode(), layout(width: params.width))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        return layout(width: params.width)
    }

    private func layout(width: CGFloat) -> AetherListItemNodeLayout {
        AetherListItemNodeLayout(contentSize: CGSize(width: width, height: height), insets: .zero)
    }
}

private final class TestNode: AetherListItemNode {}

private final class RecordingFrameReplayExecutor<NodeID: Hashable>: AetherListFrameReplayCommandExecuting {
    private(set) var commands: [AetherListFrameReplayCommand<NodeID>] = []

    func execute(_ command: AetherListFrameReplayCommand<NodeID>) {
        commands.append(command)
    }
}

private final class RecordingModelMutationExecutor<ItemID: Hashable>: AetherListModelMutationCommandExecuting {
    private(set) var commands: [AetherListModelMutationCommand<ItemID>] = []

    func execute(_ command: AetherListModelMutationCommand<ItemID>) {
        commands.append(command)
    }
}

private final class RecordingUpdateMaterializationExecutor<ItemID: Hashable, NodeID: Hashable>: AetherListUpdateMaterializationCommandExecuting {
    private(set) var commands: [AetherListUpdateMaterializationCommand<ItemID, NodeID>] = []

    func execute(_ command: AetherListUpdateMaterializationCommand<ItemID, NodeID>) {
        commands.append(command)
    }
}

private final class RecordingVisibleNodeMaterializationExecutor<NodeID: Hashable>: AetherListVisibleNodeMaterializationCommandExecuting {
    private(set) var commands: [AetherListVisibleNodeMaterializationCommand<NodeID>] = []

    func execute(_ command: AetherListVisibleNodeMaterializationCommand<NodeID>) {
        commands.append(command)
    }
}

private final class RecordingStickyHeaderExecutor<NodeID: Hashable>: AetherListStickyHeaderCommandExecuting {
    private(set) var commands: [AetherListStickyHeaderCommand<NodeID>] = []

    func execute(_ command: AetherListStickyHeaderCommand<NodeID>) {
        commands.append(command)
    }
}

private final class RecordingVirtualizationExecutor<NodeID: Hashable>: AetherListVirtualizationCommandExecuting {
    private(set) var commands: [AetherListVirtualizationCommand<NodeID>] = []

    func execute(_ command: AetherListVirtualizationCommand<NodeID>) {
        commands.append(command)
    }
}

private final class RecordingAsyncLayoutExecutor<ItemID: Hashable>: AetherListAsyncLayoutCommandExecuting {
    private(set) var commands: [AetherListAsyncLayoutCommand<ItemID>] = []

    func execute(_ command: AetherListAsyncLayoutCommand<ItemID>) {
        commands.append(command)
    }
}

private final class RecordingVisibilityLifecycleExecutor<NodeID: Hashable>: AetherListVisibilityLifecycleCommandExecuting {
    private(set) var commands: [AetherListVisibilityLifecycleCommand<NodeID>] = []

    func execute(_ command: AetherListVisibilityLifecycleCommand<NodeID>) {
        commands.append(command)
    }
}

private final class RecordingSizeAndInsetsExecutor: AetherListSizeAndInsetsCommandExecuting {
    private(set) var commands: [AetherListSizeAndInsetsCommand] = []

    func execute(_ command: AetherListSizeAndInsetsCommand) {
        commands.append(command)
    }
}

private final class RecordingScrollAnchoringExecutor: AetherListScrollAnchoringCommandExecuting {
    private(set) var commands: [AetherListScrollAnchoringCommand] = []

    func execute(_ command: AetherListScrollAnchoringCommand) {
        commands.append(command)
    }
}

private final class ControlHitTestItem: AetherListItem {
    let id: Int

    init(id: Int) {
        self.id = id
    }

    var stableId: AnyHashable { id }
    var approximateHeight: CGFloat { 44 }
    var estimatedHeight: CGFloat { 44 }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        return (ControlHitTestNode(), AetherListItemNodeLayout(contentSize: CGSize(width: params.width, height: 44)))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        return AetherListItemNodeLayout(contentSize: CGSize(width: params.width, height: 44))
    }
}

private final class ControlHitTestNode: AetherListItemNode {
    private let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        button.frame = CGRect(x: 0, y: 0, width: 80, height: bounds.height)
    }
}

private struct BadgeAccessoryItem: AetherListAccessoryItem {
    let id: String
    let text: String

    var stableId: AnyHashable { id }

    func makeView() -> UIView {
        let label = UILabel()
        label.textAlignment = .center
        return label
    }

    func updateView(_ view: UIView) {
        (view as? UILabel)?.text = text
    }

    func size(constrainedTo size: CGSize) -> CGSize {
        CGSize(width: 24, height: min(20, size.height))
    }
}

private final class AsyncPreparedItem: AetherListItem {
    let id: Int
    var didApplyPreparedLayout = false

    init(id: Int) {
        self.id = id
    }

    var stableId: AnyHashable { id }
    var approximateHeight: CGFloat { 20 }
    var estimatedHeight: CGFloat { 20 }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        return (TestNode(), fallbackLayout(width: params.width))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        return fallbackLayout(width: params.width)
    }

    @discardableResult
    func asyncLayout(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        completion: @escaping (AetherListPreparedItemLayout) -> Void
    ) -> AetherListLayoutTask? {
        completion(AetherListPreparedItemLayout(
            layout: AetherListItemNodeLayout(contentSize: CGSize(width: params.width, height: 80)),
            apply: { [weak self] _ in
                self?.didApplyPreparedLayout = true
            }
        ))
        return AetherListLayoutTask()
    }

    private func fallbackLayout(width: CGFloat) -> AetherListItemNodeLayout {
        AetherListItemNodeLayout(contentSize: CGSize(width: width, height: 20), insets: .zero)
    }
}
