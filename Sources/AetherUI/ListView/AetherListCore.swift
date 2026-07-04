import UIKit
import os

/// UIKit scroller used by `AetherListView` as the native physics engine.
///
/// Item views are mounted into `backingView`, the scroll view's single content
/// host. Keeping the native pan recognizer owned by `UIScrollView` preserves
/// UIKit bounce/deceleration while still avoiding direct cell subviews on the
/// scroll view itself.
open class AetherListScroller: UIScrollView {
    public let backingView = UIView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backingView.clipsToBounds = false
        addSubview(backingView)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backingView.clipsToBounds = false
        addSubview(backingView)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let height = max(contentSize.height, bounds.height)
        backingView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }
}

/// Public alias kept for call sites that prefer View terminology over Node.
public typealias AetherListItemView = AetherListItemNode

/// Public alias for the layout object returned by item implementations.
public typealias AetherListItemLayout = AetherListItemNodeLayout

/// Header positioning semantics. `.none` is a regular row, `.top` pins to the
/// top inset, and `.bottom` pins to the bottom inset until the header reaches
/// its natural slot.
public enum AetherListHeaderAffinity: Equatable {
    case none
    case top
    case bottom
}

public enum AetherListAccessoryPlacement: Hashable {
    case accessory
    case headerAccessory
}

/// Lightweight accessory model that `AetherListItemNode` can host without
/// knowing the row type. Existing item contracts expose `Any?` accessory hooks;
/// values that conform to this protocol are rendered automatically.
public protocol AetherListAccessoryItem {
    var stableId: AnyHashable { get }
    func makeView() -> UIView
    func updateView(_ view: UIView)
    func size(constrainedTo size: CGSize) -> CGSize
}

public extension AetherListAccessoryItem {
    var stableId: AnyHashable { String(reflecting: type(of: self)) }
}

/// Layout prepared off the main thread. The `apply` closure is always invoked
/// by `AetherListView` on the main thread after the corresponding view exists.
public struct AetherListPreparedItemLayout {
    public let layout: AetherListItemNodeLayout
    public let apply: (AetherListItemNode) -> Void

    public init(layout: AetherListItemNodeLayout, apply: @escaping (AetherListItemNode) -> Void = { _ in }) {
        self.layout = layout
        self.apply = apply
    }
}

/// Cancellable token for an async item measurement/preparation request.
public final class AetherListLayoutTask {
    private let cancelImpl: () -> Void
    private var cancelled = false

    public init(cancel: @escaping () -> Void = {}) {
        self.cancelImpl = cancel
    }

    public func cancel() {
        guard !cancelled else { return }
        cancelled = true
        cancelImpl()
    }
}

/// Atomic list mutation bundle. This mirrors the parameter-based
/// `transaction(...)` API while making queued/programmatic transaction
/// construction easier to test.
public struct AetherListTransaction {
    public var deleteIndices: [AetherListDeleteItem]
    public var moveIndices: [AetherListMoveItem]
    public var insertIndicesAndItems: [AetherListInsertItem]
    public var updateIndicesAndItems: [AetherListUpdateItem]
    public var options: AetherListTransactionOptions
    public var scrollToItem: AetherListScrollToItem?
    public var additionalScrollDistance: CGFloat
    public var updateSizeAndInsets: AetherListUpdateSizeAndInsets?
    public var stationaryItemRange: (Int, Int)?
    public var updateOpaqueState: Any?

    public init(
        deleteIndices: [AetherListDeleteItem] = [],
        moveIndices: [AetherListMoveItem] = [],
        insertIndicesAndItems: [AetherListInsertItem] = [],
        updateIndicesAndItems: [AetherListUpdateItem] = [],
        options: AetherListTransactionOptions = [],
        scrollToItem: AetherListScrollToItem? = nil,
        additionalScrollDistance: CGFloat = 0.0,
        updateSizeAndInsets: AetherListUpdateSizeAndInsets? = nil,
        stationaryItemRange: (Int, Int)? = nil,
        updateOpaqueState: Any? = nil
    ) {
        self.deleteIndices = deleteIndices
        self.moveIndices = moveIndices
        self.insertIndicesAndItems = insertIndicesAndItems
        self.updateIndicesAndItems = updateIndicesAndItems
        self.options = options
        self.scrollToItem = scrollToItem
        self.additionalScrollDistance = additionalScrollDistance
        self.updateSizeAndInsets = updateSizeAndInsets
        self.stationaryItemRange = stationaryItemRange
        self.updateOpaqueState = updateOpaqueState
    }
}

/// Pure item descriptor used by `AetherListIntermediateState`. It intentionally
/// stores only identity and height, which keeps transaction math independent
/// from UIKit view/node lifetime.
public struct AetherListIntermediateItem: Equatable {
    public let stableId: AnyHashable
    public let height: CGFloat

    public init(stableId: AnyHashable, height: CGFloat) {
        self.stableId = stableId
        self.height = max(0.0, height)
    }
}

public struct AetherListIntermediateInsertItem: Equatable {
    public let index: Int
    public let item: AetherListIntermediateItem

    public init(index: Int, item: AetherListIntermediateItem) {
        self.index = index
        self.item = item
    }
}

public struct AetherListIntermediateUpdateItem: Equatable {
    public let index: Int
    public let previousIndex: Int
    public let item: AetherListIntermediateItem

    public init(index: Int, previousIndex: Int, item: AetherListIntermediateItem) {
        self.index = index
        self.previousIndex = previousIndex
        self.item = item
    }
}

public struct AetherListIntermediateAnchor: Equatable {
    public let stableId: AnyHashable
    public let index: Int
    public let offset: CGFloat

    public init(stableId: AnyHashable, index: Int, offset: CGFloat) {
        self.stableId = stableId
        self.index = index
        self.offset = offset
    }
}

/// Immutable, UIKit-free state for Telegram-style transaction math. The live
/// list still owns node reuse and animation replay, but index shifts, stable-id
/// anchoring, and offset deltas can be validated without materialising views.
public struct AetherListIntermediateState: Equatable {
    public let items: [AetherListIntermediateItem]
    public let itemOffsetInsets: UIEdgeInsets
    public let itemOffsets: [CGFloat]
    public let totalContentHeight: CGFloat

    public init(items: [AetherListIntermediateItem], itemOffsetInsets: UIEdgeInsets = .zero) {
        self.items = items
        self.itemOffsetInsets = itemOffsetInsets
        let metrics = AetherListFrameMetrics.rebuildOffsets(
            heights: items.map(\.height),
            offsetInsets: itemOffsetInsets
        )
        self.itemOffsets = metrics.offsets
        self.totalContentHeight = metrics.totalHeight
    }

    public init(stableIds: [AnyHashable], heights: [CGFloat], itemOffsetInsets: UIEdgeInsets = .zero) {
        let count = min(stableIds.count, heights.count)
        let items = (0..<count).map { index in
            AetherListIntermediateItem(stableId: stableIds[index], height: heights[index])
        }
        self.init(items: items, itemOffsetInsets: itemOffsetInsets)
    }

    public func index(of stableId: AnyHashable) -> Int? {
        return items.firstIndex { $0.stableId == stableId }
    }

    public func itemOffset(at index: Int) -> CGFloat? {
        guard index >= 0, index < itemOffsets.count else { return nil }
        return itemOffsets[index]
    }

    public func stationaryAnchor(
        in range: (Int, Int)?,
        loadedIndices: Set<Int>? = nil
    ) -> AetherListIntermediateAnchor? {
        guard let range, !items.isEmpty else { return nil }
        let lower = max(0, min(range.0, range.1))
        let upper = min(items.count - 1, max(range.0, range.1))
        guard lower <= upper else { return nil }

        for index in lower...upper {
            if let loadedIndices, !loadedIndices.contains(index) {
                continue
            }
            guard let offset = itemOffset(at: index) else { continue }
            return AetherListIntermediateAnchor(
                stableId: items[index].stableId,
                index: index,
                offset: offset
            )
        }
        return nil
    }

    public func offsetDelta(preserving anchor: AetherListIntermediateAnchor) -> CGFloat? {
        guard let newIndex = index(of: anchor.stableId),
              let newOffset = itemOffset(at: newIndex) else {
            return nil
        }
        return newOffset - anchor.offset
    }

    public func applying(
        deleteIndices: [Int] = [],
        moveIndices: [(fromIndex: Int, toIndex: Int)] = [],
        insertItems: [AetherListIntermediateInsertItem] = [],
        updateItems: [AetherListIntermediateUpdateItem] = []
    ) -> AetherListIntermediateState {
        var nextItems = items

        for index in deleteIndices.sorted(by: >) {
            guard index >= 0, index < nextItems.count else { continue }
            nextItems.remove(at: index)
        }

        for move in moveIndices {
            guard move.fromIndex >= 0,
                  move.fromIndex < nextItems.count,
                  move.toIndex >= 0,
                  move.toIndex <= nextItems.count else {
                continue
            }
            let item = nextItems.remove(at: move.fromIndex)
            let target = min(move.toIndex, nextItems.count)
            nextItems.insert(item, at: target)
        }

        for insert in insertItems.sorted(by: { $0.index < $1.index }) {
            let index = min(max(0, insert.index), nextItems.count)
            nextItems.insert(insert.item, at: index)
        }

        for update in updateItems {
            guard update.index >= 0, update.index < nextItems.count else { continue }
            nextItems[update.index] = update.item
        }

        return AetherListIntermediateState(items: nextItems, itemOffsetInsets: itemOffsetInsets)
    }
}

/// Internal state-operation vocabulary used by the transaction planner and
/// tests. The live view still replays directly against UIKit views for now.
public enum AetherListStateOperation: Equatable {
    case delete(index: Int)
    case insert(index: Int)
    case update(index: Int)
    case move(fromIndex: Int, toIndex: Int)
    case remap([Int: Int])
}

/// Immutable output from the pure transaction planner. `AetherListView` still
/// owns UIKit replay, but index/remap math is centralized here so callers and
/// tests do not have to exercise live views for state-only validation.
public struct AetherListTransactionPlan: Equatable {
    public let operations: [AetherListStateOperation]
    public let deletionRemap: [Int: Int]
    public let insertionRemap: [Int: Int]
    public let beforeState: AetherListIntermediateState?
    public let afterState: AetherListIntermediateState?

    public init(
        operations: [AetherListStateOperation],
        deletionRemap: [Int: Int],
        insertionRemap: [Int: Int],
        beforeState: AetherListIntermediateState? = nil,
        afterState: AetherListIntermediateState? = nil
    ) {
        self.operations = operations
        self.deletionRemap = deletionRemap
        self.insertionRemap = insertionRemap
        self.beforeState = beforeState
        self.afterState = afterState
    }
}

public enum AetherListTransactionPlanner {
    public static func plan(
        itemCount: Int,
        deleteIndices: [Int] = [],
        insertIndices: [Int] = [],
        moveIndices: [(fromIndex: Int, toIndex: Int)] = [],
        updateIndices: [Int] = []
    ) -> AetherListTransactionPlan {
        let validDeletes = deleteIndices
            .filter { $0 >= 0 && $0 < itemCount }
            .sorted()
        let deletionRemap = AetherListFrameMetrics.deletionRemap(
            itemCount: itemCount,
            deletedIndices: validDeletes
        )

        let survivingIndices = (0..<itemCount).filter { !validDeletes.contains($0) }
        let insertionRemap = AetherListFrameMetrics.insertionRemap(
            survivingIndices: survivingIndices,
            insertedIndices: insertIndices.filter { $0 >= 0 }
        )

        var operations: [AetherListStateOperation] = []
        operations.append(contentsOf: validDeletes.map { .delete(index: $0) })
        operations.append(contentsOf: moveIndices
            .filter { $0.fromIndex >= 0 && $0.toIndex >= 0 }
            .map { .move(fromIndex: $0.fromIndex, toIndex: $0.toIndex) })
        operations.append(contentsOf: insertIndices
            .filter { $0 >= 0 }
            .sorted()
            .map { .insert(index: $0) })
        operations.append(contentsOf: updateIndices
            .filter { $0 >= 0 }
            .sorted()
            .map { .update(index: $0) })
        if !deletionRemap.isEmpty {
            operations.append(.remap(deletionRemap))
        }

        return AetherListTransactionPlan(
            operations: operations,
            deletionRemap: deletionRemap,
            insertionRemap: insertionRemap
        )
    }

    public static func plan(
        state: AetherListIntermediateState,
        deleteIndices: [Int] = [],
        insertItems: [AetherListIntermediateInsertItem] = [],
        moveIndices: [(fromIndex: Int, toIndex: Int)] = [],
        updateItems: [AetherListIntermediateUpdateItem] = []
    ) -> AetherListTransactionPlan {
        let basePlan = plan(
            itemCount: state.items.count,
            deleteIndices: deleteIndices,
            insertIndices: insertItems.map(\.index),
            moveIndices: moveIndices,
            updateIndices: updateItems.map(\.index)
        )
        let afterState = state.applying(
            deleteIndices: deleteIndices,
            moveIndices: moveIndices,
            insertItems: insertItems,
            updateItems: updateItems
        )
        return AetherListTransactionPlan(
            operations: basePlan.operations,
            deletionRemap: basePlan.deletionRemap,
            insertionRemap: basePlan.insertionRemap,
            beforeState: state,
            afterState: afterState
        )
    }
}

internal enum AetherListNodeUpdateReplayAnimation: Equatable {
    case none
    case crossfade
    case fullTransition(duration: Double)
}

internal enum AetherListNodeInsertionReplayAnimation: Equatable {
    case none
    case alphaFade(duration: Double)
    case item(duration: Double, directionHint: AetherListItemOperationDirectionHint?, invertOffsetDirection: Bool)
}

internal enum AetherListNodeFrameReplayCurve: Equatable {
    case standard
    case easeOut
}

internal enum AetherListNodeFrameReplayAnimation: Equatable {
    case none
    case animated(duration: Double, curve: AetherListNodeFrameReplayCurve)
}

/// UIKit-free transaction replay policy. `AetherListView` still performs the
/// actual view mutations, but the decision layer that chooses insertion,
/// removal, update, and neighbour-frame animations is centralized here.
internal struct AetherListNodeReplayPlan: Equatable {
    let animatesStructuralChanges: Bool
    let usesAlphaAnimations: Bool
    let updateAnimation: AetherListNodeUpdateReplayAnimation
    let survivingFrameAnimation: AetherListNodeFrameReplayAnimation
    let baseDuration: Double

    static func make(
        options: AetherListTransactionOptions,
        hasForcedInsertionAnimation: Bool,
        hasParticleDissolveRemoval: Bool,
        baseDuration: Double,
        particleDissolveDuration: Double,
        reduceMotionEnabled: Bool
    ) -> AetherListNodeReplayPlan {
        let wantsStructuralAnimation = options.contains(.animateInsertions)
            || options.contains(.requestItemInsertionAnimations)
            || options.contains(.animateFullTransition)
            || hasForcedInsertionAnimation
        let animatesStructuralChanges = wantsStructuralAnimation && !reduceMotionEnabled
        let usesAlphaAnimations = animatesStructuralChanges && options.contains(.animateAlpha)

        let updateAnimation: AetherListNodeUpdateReplayAnimation
        if reduceMotionEnabled {
            updateAnimation = .none
        } else if options.contains(.crossfade) {
            updateAnimation = .crossfade
        } else if options.contains(.animateFullTransition) {
            updateAnimation = .fullTransition(duration: baseDuration)
        } else {
            updateAnimation = .none
        }

        let survivingFrameAnimation: AetherListNodeFrameReplayAnimation
        if animatesStructuralChanges {
            survivingFrameAnimation = .animated(
                duration: hasParticleDissolveRemoval ? particleDissolveDuration : baseDuration,
                curve: hasParticleDissolveRemoval ? .easeOut : .standard
            )
        } else {
            survivingFrameAnimation = .none
        }

        return AetherListNodeReplayPlan(
            animatesStructuralChanges: animatesStructuralChanges,
            usesAlphaAnimations: usesAlphaAnimations,
            updateAnimation: updateAnimation,
            survivingFrameAnimation: survivingFrameAnimation,
            baseDuration: baseDuration
        )
    }

    func insertionAnimation(
        isNewNode: Bool,
        forceItemAnimation: Bool,
        directionHint: AetherListItemOperationDirectionHint?,
        invertOffsetDirection: Bool
    ) -> AetherListNodeInsertionReplayAnimation {
        guard isNewNode, animatesStructuralChanges else {
            return .none
        }
        if usesAlphaAnimations {
            return .alphaFade(duration: min(baseDuration, 0.1))
        }
        guard forceItemAnimation || animatesStructuralChanges else {
            return .none
        }
        return .item(
            duration: baseDuration,
            directionHint: directionHint,
            invertOffsetDirection: invertOffsetDirection
        )
    }

    func deletionAnimation(for animation: AetherListItemDeleteAnimation) -> AetherListItemDeleteAnimation? {
        guard animatesStructuralChanges else {
            return nil
        }
        guard usesAlphaAnimations else {
            return animation
        }
        if case .particleDissolve = animation {
            return animation
        }
        return .fade
    }
}

internal struct AetherListNodeMaterializationCommand<NodeID: Hashable>: Equatable {
    let nodeId: NodeID
    let previousIndex: Int
    let targetIndex: Int
    let duplicateTargetNodeId: NodeID?
}

/// Value-type node allocation state for transaction replay. It does not create,
/// recycle, or mutate UIKit views; it only emits immutable commands describing
/// which pre-transaction node may be reused for a target index and which loaded
/// target node must be displaced first.
internal struct AetherListNodeMaterializationPlanner<NodeID: Hashable> {
    private let previousNodeByIndex: [Int: NodeID]
    private var currentNodeByIndex: [Int: NodeID]
    private var consumedPreviousNodeIds = Set<NodeID>()

    init(previousNodeByIndex: [Int: NodeID], currentNodeByIndex: [Int: NodeID]) {
        self.previousNodeByIndex = previousNodeByIndex
        self.currentNodeByIndex = currentNodeByIndex
    }

    mutating func takePreviousNode(previousIndex: Int, targetIndex: Int) -> AetherListNodeMaterializationCommand<NodeID>? {
        guard previousIndex >= 0, targetIndex >= 0 else {
            return nil
        }
        guard let nodeId = previousNodeByIndex[previousIndex],
              !consumedPreviousNodeIds.contains(nodeId) else {
            return nil
        }
        consumedPreviousNodeIds.insert(nodeId)

        let duplicateTargetNodeId = currentNodeByIndex[targetIndex].flatMap { existing in
            existing == nodeId ? nil : existing
        }
        let staleIndicesForNode = currentNodeByIndex.compactMap { index, existingNodeId in
            existingNodeId == nodeId ? index : nil
        }
        for index in staleIndicesForNode {
            currentNodeByIndex.removeValue(forKey: index)
        }
        currentNodeByIndex[targetIndex] = nodeId

        return AetherListNodeMaterializationCommand(
            nodeId: nodeId,
            previousIndex: previousIndex,
            targetIndex: targetIndex,
            duplicateTargetNodeId: duplicateTargetNodeId
        )
    }

    func currentNodeId(at index: Int) -> NodeID? {
        currentNodeByIndex[index]
    }
}

internal struct AetherListModelMutationInsertDescriptor<ItemID: Hashable>: Equatable {
    let sourceIndex: Int
    let requestedIndex: Int
    let itemId: ItemID
    let estimatedHeight: CGFloat
    let previousIndex: Int?
    let directionHint: AetherListItemOperationDirectionHint?
    let forceAnimateInsertion: Bool
}

internal enum AetherListModelMutationCommand<ItemID: Hashable>: Equatable {
    case delete(
        index: Int,
        itemId: ItemID,
        animation: AetherListItemDeleteAnimation,
        hint: AetherListItemOperationDirectionHint?
    )
    case move(fromIndex: Int, toIndex: Int)
    case insert(index: Int, descriptor: AetherListModelMutationInsertDescriptor<ItemID>)
}

internal struct AetherListModelMutationPlan<ItemID: Hashable>: Equatable {
    let commands: [AetherListModelMutationCommand<ItemID>]
    let itemIds: [ItemID]
    let itemHeights: [CGFloat]
    let insertPreviousIndexByTargetIndex: [Int: Int]
    let insertDirectionHintByTargetIndex: [Int: AetherListItemOperationDirectionHint]
    let forceAnimateInsertionIndices: Set<Int>
}

internal protocol AetherListModelMutationCommandExecuting {
    associatedtype ItemID: Hashable
    func execute(_ command: AetherListModelMutationCommand<ItemID>)
}

internal enum AetherListModelMutationCommandPlanner {
    static func plan<ItemID: Hashable>(
        itemIds: [ItemID],
        itemHeights: [CGFloat],
        deleteItems: [AetherListDeleteItem],
        moveItems: [AetherListMoveItem],
        insertDescriptors: [AetherListModelMutationInsertDescriptor<ItemID>]
    ) -> AetherListModelMutationPlan<ItemID> {
        let count = min(itemIds.count, itemHeights.count)
        var currentItemIds = Array(itemIds.prefix(count))
        var currentHeights = Array(itemHeights.prefix(count))
        var commands: [AetherListModelMutationCommand<ItemID>] = []

        for delete in deleteItems.sorted(by: { $0.index > $1.index }) {
            guard delete.index >= 0, delete.index < currentItemIds.count else {
                continue
            }
            commands.append(.delete(
                index: delete.index,
                itemId: currentItemIds[delete.index],
                animation: delete.animation,
                hint: delete.directionHint
            ))
            currentItemIds.remove(at: delete.index)
            currentHeights.remove(at: delete.index)
        }

        for move in moveItems {
            guard move.fromIndex >= 0,
                  move.fromIndex < currentItemIds.count,
                  move.toIndex >= 0,
                  move.toIndex <= currentItemIds.count else {
                continue
            }
            let itemId = currentItemIds.remove(at: move.fromIndex)
            let height = currentHeights.remove(at: move.fromIndex)
            let targetIndex = min(move.toIndex, currentItemIds.count)
            commands.append(.move(fromIndex: move.fromIndex, toIndex: targetIndex))
            currentItemIds.insert(itemId, at: targetIndex)
            currentHeights.insert(height, at: targetIndex)
        }

        var insertPreviousIndexByTargetIndex: [Int: Int] = [:]
        var insertDirectionHintByTargetIndex: [Int: AetherListItemOperationDirectionHint] = [:]
        var forceAnimateInsertionIndices = Set<Int>()
        let sortedInsertDescriptors = insertDescriptors.sorted {
            if $0.requestedIndex == $1.requestedIndex {
                return $0.sourceIndex < $1.sourceIndex
            }
            return $0.requestedIndex < $1.requestedIndex
        }

        for descriptor in sortedInsertDescriptors {
            let index = min(max(0, descriptor.requestedIndex), currentItemIds.count)
            commands.append(.insert(index: index, descriptor: descriptor))
            currentItemIds.insert(descriptor.itemId, at: index)
            currentHeights.insert(descriptor.estimatedHeight, at: index)
            if let previousIndex = descriptor.previousIndex {
                insertPreviousIndexByTargetIndex[index] = previousIndex
            }
            if let directionHint = descriptor.directionHint {
                insertDirectionHintByTargetIndex[index] = directionHint
            }
            if descriptor.forceAnimateInsertion {
                forceAnimateInsertionIndices.insert(index)
            }
        }

        return AetherListModelMutationPlan(
            commands: commands,
            itemIds: currentItemIds,
            itemHeights: currentHeights,
            insertPreviousIndexByTargetIndex: insertPreviousIndexByTargetIndex,
            insertDirectionHintByTargetIndex: insertDirectionHintByTargetIndex,
            forceAnimateInsertionIndices: forceAnimateInsertionIndices
        )
    }
}

internal struct AetherListUpdateMaterializationDescriptor<ItemID: Hashable>: Equatable {
    let sourceIndex: Int
    let index: Int
    let previousIndex: Int
    let itemId: ItemID
    let estimatedHeight: CGFloat
}

internal enum AetherListUpdateMaterializationNodeSource<NodeID: Hashable>: Equatable {
    case previous(AetherListNodeMaterializationCommand<NodeID>)
    case current(NodeID)
}

internal enum AetherListUpdateMaterializationCommand<ItemID: Hashable, NodeID: Hashable>: Equatable {
    case materialize(
        index: Int,
        sourceIndex: Int,
        itemId: ItemID,
        nodeSource: AetherListUpdateMaterializationNodeSource<NodeID>
    )
    case setEstimatedHeight(
        index: Int,
        sourceIndex: Int,
        itemId: ItemID,
        height: CGFloat
    )
}

internal protocol AetherListUpdateMaterializationCommandExecuting {
    associatedtype ItemID: Hashable
    associatedtype NodeID: Hashable
    mutating func execute(_ command: AetherListUpdateMaterializationCommand<ItemID, NodeID>)
}

internal enum AetherListUpdateMaterializationCommandPlanner {
    static func commands<ItemID: Hashable, NodeID: Hashable>(
        descriptors: [AetherListUpdateMaterializationDescriptor<ItemID>],
        itemCount: Int,
        materializationPlanner: inout AetherListNodeMaterializationPlanner<NodeID>
    ) -> [AetherListUpdateMaterializationCommand<ItemID, NodeID>] {
        var commands: [AetherListUpdateMaterializationCommand<ItemID, NodeID>] = []
        commands.reserveCapacity(descriptors.count)

        for descriptor in descriptors {
            guard descriptor.index >= 0,
                  descriptor.index < itemCount else {
                continue
            }

            if let previousCommand = materializationPlanner.takePreviousNode(
                previousIndex: descriptor.previousIndex,
                targetIndex: descriptor.index
            ) {
                commands.append(.materialize(
                    index: descriptor.index,
                    sourceIndex: descriptor.sourceIndex,
                    itemId: descriptor.itemId,
                    nodeSource: .previous(previousCommand)
                ))
            } else if let currentNodeId = materializationPlanner.currentNodeId(at: descriptor.index) {
                commands.append(.materialize(
                    index: descriptor.index,
                    sourceIndex: descriptor.sourceIndex,
                    itemId: descriptor.itemId,
                    nodeSource: .current(currentNodeId)
                ))
            } else {
                commands.append(.setEstimatedHeight(
                    index: descriptor.index,
                    sourceIndex: descriptor.sourceIndex,
                    itemId: descriptor.itemId,
                    height: descriptor.estimatedHeight
                ))
            }
        }

        return commands
    }
}

internal enum AetherListVisibleNodeMaterializationSource<NodeID: Hashable>: Equatable {
    case previous(AetherListNodeMaterializationCommand<NodeID>)
    case reusableOrCreated
}

internal enum AetherListVisibleNodeMaterializationCommand<NodeID: Hashable>: Equatable {
    case mount(index: Int, source: AetherListVisibleNodeMaterializationSource<NodeID>)
}

internal protocol AetherListVisibleNodeMaterializationCommandExecuting {
    associatedtype NodeID: Hashable
    mutating func execute(_ command: AetherListVisibleNodeMaterializationCommand<NodeID>)
}

internal enum AetherListVisibleNodeMaterializationCommandPlanner {
    static func commands<NodeID: Hashable>(
        visibleRange: Range<Int>,
        insertPreviousIndexByTargetIndex: [Int: Int],
        materializationPlanner: inout AetherListNodeMaterializationPlanner<NodeID>
    ) -> [AetherListVisibleNodeMaterializationCommand<NodeID>] {
        var commands: [AetherListVisibleNodeMaterializationCommand<NodeID>] = []
        commands.reserveCapacity(visibleRange.count)

        for index in visibleRange {
            if materializationPlanner.currentNodeId(at: index) != nil {
                continue
            }

            if let previousIndex = insertPreviousIndexByTargetIndex[index],
               let previousCommand = materializationPlanner.takePreviousNode(
                    previousIndex: previousIndex,
                    targetIndex: index
               ) {
                commands.append(.mount(index: index, source: .previous(previousCommand)))
            } else {
                commands.append(.mount(index: index, source: .reusableOrCreated))
            }
        }

        return commands
    }
}

internal struct AetherListStickyHeaderDescriptor<NodeID: Hashable>: Equatable {
    let index: Int
    let affinity: AetherListHeaderAffinity
    let naturalY: CGFloat
    let height: CGFloat
    let nodeId: NodeID?
}

internal enum AetherListStickyHeaderCommand<NodeID: Hashable>: Equatable {
    case ensureNode(index: Int)
    case applyLayout(
        nodeId: NodeID,
        index: Int,
        frame: CGRect,
        state: AetherListStickyHeaderState,
        zPosition: CGFloat,
        bringToFront: Bool
    )
}

internal protocol AetherListStickyHeaderCommandExecuting {
    associatedtype NodeID: Hashable
    mutating func execute(_ command: AetherListStickyHeaderCommand<NodeID>)
}

internal enum AetherListStickyHeaderCommandPlanner {
    static func pinnedIndices<NodeID: Hashable>(
        descriptors: [AetherListStickyHeaderDescriptor<NodeID>],
        viewportTop: CGFloat,
        viewportBottom: CGFloat
    ) -> Set<Int> {
        var result = Set<Int>()
        if let topIndex = currentTopStickyHeaderIndex(
            descriptors: descriptors,
            viewportTop: viewportTop
        ) {
            result.insert(topIndex)
        }
        if let bottomIndex = currentBottomStickyHeaderIndex(
            descriptors: descriptors,
            viewportBottom: viewportBottom
        ) {
            result.insert(bottomIndex)
        }
        return result
    }

    static func commands<NodeID: Hashable>(
        descriptors: [AetherListStickyHeaderDescriptor<NodeID>],
        viewportTop: CGFloat,
        viewportBottom: CGFloat,
        boundsWidth: CGFloat,
        displayScale: CGFloat
    ) -> [AetherListStickyHeaderCommand<NodeID>] {
        let orderedDescriptors = descriptors.sorted { $0.index < $1.index }
        let pinnedHeaderIndices = pinnedIndices(
            descriptors: orderedDescriptors,
            viewportTop: viewportTop,
            viewportBottom: viewportBottom
        )
        var commands: [AetherListStickyHeaderCommand<NodeID>] = []

        for descriptor in orderedDescriptors where pinnedHeaderIndices.contains(descriptor.index) && descriptor.nodeId == nil {
            commands.append(.ensureNode(index: descriptor.index))
        }

        let topDescriptors = orderedDescriptors.filter { $0.affinity == .top }
        for (offset, descriptor) in topDescriptors.enumerated() {
            guard let nodeId = descriptor.nodeId else { continue }
            let nextNaturalY: CGFloat = (offset + 1 < topDescriptors.count)
                ? topDescriptors[offset + 1].naturalY
                : .greatestFiniteMagnitude
            let isPinned = descriptor.naturalY <= viewportTop
                && (nextNaturalY - descriptor.height) > viewportTop
            let maxStickY = nextNaturalY - descriptor.height
            let targetY: CGFloat
            if descriptor.naturalY <= viewportTop {
                targetY = min(maxStickY, max(viewportTop, descriptor.naturalY))
            } else {
                targetY = descriptor.naturalY
            }
            appendApplyCommand(
                nodeId: nodeId,
                descriptor: descriptor,
                targetY: targetY,
                isPinned: isPinned,
                boundsWidth: boundsWidth,
                displayScale: displayScale,
                commands: &commands
            )
        }

        let bottomPinnedIndex = currentBottomStickyHeaderIndex(
            descriptors: orderedDescriptors,
            viewportBottom: viewportBottom
        )
        for descriptor in orderedDescriptors where descriptor.affinity == .bottom {
            guard let nodeId = descriptor.nodeId else { continue }
            let pinnedY = viewportBottom - descriptor.height
            let isPinned = descriptor.index == bottomPinnedIndex && descriptor.naturalY > pinnedY
            let targetY = isPinned ? pinnedY : descriptor.naturalY
            appendApplyCommand(
                nodeId: nodeId,
                descriptor: descriptor,
                targetY: targetY,
                isPinned: isPinned,
                boundsWidth: boundsWidth,
                displayScale: displayScale,
                commands: &commands
            )
        }

        return commands
    }

    private static func appendApplyCommand<NodeID: Hashable>(
        nodeId: NodeID,
        descriptor: AetherListStickyHeaderDescriptor<NodeID>,
        targetY: CGFloat,
        isPinned: Bool,
        boundsWidth: CGFloat,
        displayScale: CGFloat,
        commands: inout [AetherListStickyHeaderCommand<NodeID>]
    ) {
        let isFloating = abs(targetY - descriptor.naturalY) > 0.5
        let shouldOverlay = isPinned || isFloating
        let state = shouldOverlay
            ? AetherListStickyHeaderState(
                affinity: descriptor.affinity,
                isPinned: isPinned,
                isFloating: isFloating,
                isFlashing: isFloating
            )
            : .none
        let frame = AetherListFrameMetrics.pixelAligned(
            CGRect(
                x: 0,
                y: targetY,
                width: boundsWidth,
                height: descriptor.height
            ),
            scale: displayScale
        )
        commands.append(.applyLayout(
            nodeId: nodeId,
            index: descriptor.index,
            frame: frame,
            state: state,
            zPosition: shouldOverlay ? 1000 : 0,
            bringToFront: shouldOverlay
        ))
    }

    private static func currentTopStickyHeaderIndex<NodeID: Hashable>(
        descriptors: [AetherListStickyHeaderDescriptor<NodeID>],
        viewportTop: CGFloat
    ) -> Int? {
        var found: Int?
        for descriptor in descriptors.sorted(by: { $0.index < $1.index }) where descriptor.affinity == .top {
            if descriptor.naturalY <= viewportTop {
                found = descriptor.index
            } else {
                break
            }
        }
        return found
    }

    private static func currentBottomStickyHeaderIndex<NodeID: Hashable>(
        descriptors: [AetherListStickyHeaderDescriptor<NodeID>],
        viewportBottom: CGFloat
    ) -> Int? {
        for descriptor in descriptors.sorted(by: { $0.index < $1.index }) where descriptor.affinity == .bottom {
            if descriptor.naturalY > viewportBottom - descriptor.height {
                return descriptor.index
            }
        }
        return nil
    }
}

internal struct AetherListVirtualizationLoadedNode<NodeID: Hashable>: Equatable {
    let nodeId: NodeID
    let index: Int?
    let isProtected: Bool
}

internal enum AetherListVirtualizationCommand<NodeID: Hashable>: Equatable {
    case recycle(nodeId: NodeID, index: Int)
    case mount(index: Int)
    case setFrame(nodeId: NodeID, index: Int, frame: CGRect)
}

internal protocol AetherListVirtualizationCommandExecuting {
    associatedtype NodeID: Hashable
    mutating func execute(_ command: AetherListVirtualizationCommand<NodeID>)
}

internal enum AetherListVirtualizationCommandPlanner {
    static func commands<NodeID: Hashable>(
        visibleRange: Range<Int>,
        pinnedIndices: Set<Int>,
        loadedNodes: [AetherListVirtualizationLoadedNode<NodeID>],
        itemOffsets: [CGFloat],
        itemHeights: [CGFloat],
        boundsWidth: CGFloat,
        displayScale: CGFloat
    ) -> [AetherListVirtualizationCommand<NodeID>] {
        var commands: [AetherListVirtualizationCommand<NodeID>] = []
        var retainedNodes: [AetherListVirtualizationLoadedNode<NodeID>] = []
        var retainedIndices = Set<Int>()

        for node in loadedNodes {
            guard let index = node.index else {
                retainedNodes.append(node)
                continue
            }

            if !node.isProtected,
               !visibleRange.contains(index),
               !pinnedIndices.contains(index) {
                commands.append(.recycle(nodeId: node.nodeId, index: index))
            } else {
                retainedNodes.append(node)
                retainedIndices.insert(index)
            }
        }

        for index in visibleRange where !retainedIndices.contains(index) {
            commands.append(.mount(index: index))
            retainedIndices.insert(index)
        }

        for node in retainedNodes {
            guard let index = node.index,
                  index >= 0,
                  index < itemOffsets.count,
                  index < itemHeights.count else {
                continue
            }
            commands.append(.setFrame(
                nodeId: node.nodeId,
                index: index,
                frame: AetherListFrameMetrics.pixelAligned(
                    CGRect(
                        x: 0,
                        y: itemOffsets[index],
                        width: boundsWidth,
                        height: itemHeights[index]
                    ),
                    scale: displayScale
                )
            ))
        }

        return commands
    }
}

internal struct AetherListAsyncLayoutItemDescriptor<ItemID: Hashable>: Equatable {
    let index: Int
    let itemId: ItemID
    let reuseIdentifier: String
    let hasPreparedLayout: Bool
    let hasPendingLayoutTask: Bool
    let isKnownSynchronous: Bool
}

internal enum AetherListAsyncLayoutCommand<ItemID: Hashable>: Equatable {
    case cancel(itemId: ItemID)
    case prepare(index: Int, itemId: ItemID)
}

internal protocol AetherListAsyncLayoutCommandExecuting {
    associatedtype ItemID: Hashable
    mutating func execute(_ command: AetherListAsyncLayoutCommand<ItemID>)
}

internal enum AetherListAsyncLayoutCommandPlanner {
    static func commands<ItemID: Hashable>(
        prefetchRange: Range<Int>,
        itemDescriptors: [AetherListAsyncLayoutItemDescriptor<ItemID>]
    ) -> [AetherListAsyncLayoutCommand<ItemID>] {
        var commands: [AetherListAsyncLayoutCommand<ItemID>] = []
        let idsInsidePrefetchRange = Set(
            itemDescriptors.lazy
                .filter { prefetchRange.contains($0.index) }
                .map(\.itemId)
        )

        var cancelledItemIds = Set<ItemID>()
        for descriptor in itemDescriptors where descriptor.hasPendingLayoutTask {
            guard !idsInsidePrefetchRange.contains(descriptor.itemId),
                  cancelledItemIds.insert(descriptor.itemId).inserted else {
                continue
            }
            commands.append(.cancel(itemId: descriptor.itemId))
        }

        let descriptorByIndex = Dictionary(uniqueKeysWithValues: itemDescriptors.map { ($0.index, $0) })
        var requestedItemIds = Set<ItemID>()
        for index in prefetchRange {
            guard let descriptor = descriptorByIndex[index],
                  requestedItemIds.insert(descriptor.itemId).inserted,
                  !descriptor.hasPreparedLayout,
                  !descriptor.hasPendingLayoutTask,
                  !descriptor.isKnownSynchronous else {
                continue
            }
            commands.append(.prepare(index: index, itemId: descriptor.itemId))
        }

        return commands
    }
}

internal struct AetherListVisibilityNodeDescriptor<NodeID: Hashable>: Equatable {
    let nodeId: NodeID
    let index: Int?
    let frame: CGRect
    let isAccessibilityVisible: Bool
}

internal struct AetherListVisibilitySnapshot<NodeID: Hashable>: Equatable {
    let displayedRange: AetherListDisplayedItemRange
    let accessibilityNodeIds: [NodeID]
    let loadedViewCount: Int
}

internal enum AetherListVisibilityLifecycleCommand<NodeID: Hashable>: Equatable {
    case recordVisibleViews(count: Int)
    case setAccessibilityOrder(nodeIds: [NodeID])
    case notifyDisplayedRange(AetherListDisplayedItemRange)
}

internal protocol AetherListVisibilityLifecycleCommandExecuting {
    associatedtype NodeID: Hashable
    func execute(_ command: AetherListVisibilityLifecycleCommand<NodeID>)
}

internal enum AetherListVisibilityLifecycleCommandPlanner {
    static func snapshot<NodeID: Hashable>(
        nodeDescriptors: [AetherListVisibilityNodeDescriptor<NodeID>],
        viewportTop: CGFloat,
        viewportHeight: CGFloat
    ) -> AetherListVisibilitySnapshot<NodeID> {
        let indexedDescriptors = nodeDescriptors.compactMap { descriptor -> AetherListVisibilityNodeDescriptor<NodeID>? in
            descriptor.index == nil ? nil : descriptor
        }
        let loadedIndices = indexedDescriptors.compactMap(\.index)
        let loadedRange: Range<Int>?
        if let first = loadedIndices.min(), let last = loadedIndices.max() {
            loadedRange = first ..< (last + 1)
        } else {
            loadedRange = nil
        }

        let viewportBottom = viewportTop + viewportHeight
        let visibleDescriptors = indexedDescriptors
            .filter { descriptor in
                descriptor.frame.maxY > viewportTop && descriptor.frame.minY < viewportBottom
            }
            .sorted { lhs, rhs in
                (lhs.index ?? Int.max) < (rhs.index ?? Int.max)
            }
        let visibleRange: Range<Int>?
        let visibleItemRange: AetherListVisibleItemRange?
        if let first = visibleDescriptors.first?.index,
           let last = visibleDescriptors.last?.index {
            visibleRange = first ..< (last + 1)
            let firstFrame = visibleDescriptors[0].frame
            visibleItemRange = AetherListVisibleItemRange(
                firstIndex: first,
                firstIndexFullyVisible: firstFrame.minY >= viewportTop && firstFrame.maxY <= viewportBottom,
                lastIndex: last
            )
        } else {
            visibleRange = nil
            visibleItemRange = nil
        }

        let accessibilityNodeIds = nodeDescriptors
            .filter(\.isAccessibilityVisible)
            .sorted { lhs, rhs in
                (lhs.index ?? Int.max) < (rhs.index ?? Int.max)
            }
            .map(\.nodeId)

        return AetherListVisibilitySnapshot(
            displayedRange: AetherListDisplayedItemRange(
                loadedRange: loadedRange,
                visibleRange: visibleRange,
                visibleItemRange: visibleItemRange
            ),
            accessibilityNodeIds: accessibilityNodeIds,
            loadedViewCount: nodeDescriptors.count
        )
    }

    static func commands<NodeID: Hashable>(
        snapshot: AetherListVisibilitySnapshot<NodeID>,
        notifyDisplayedRange: Bool
    ) -> [AetherListVisibilityLifecycleCommand<NodeID>] {
        var commands: [AetherListVisibilityLifecycleCommand<NodeID>] = [
            .recordVisibleViews(count: snapshot.loadedViewCount),
            .setAccessibilityOrder(nodeIds: snapshot.accessibilityNodeIds)
        ]
        if notifyDisplayedRange {
            commands.append(.notifyDisplayedRange(snapshot.displayedRange))
        }
        return commands
    }
}

internal struct AetherListBoundaryTriggerSnapshot: Equatable {
    let itemCount: Int
    let displayedRange: AetherListDisplayedItemRange
    let visibleContentOffset: CGFloat
    let visibleBottomContentOffset: CGFloat
    let isUserInitiated: Bool
}

internal struct AetherListBoundaryTrigger: Equatable {
    let edge: AetherListBoundaryEdge
    let reasons: [AetherListBoundaryTriggerReason]
}

internal enum AetherListBoundaryTriggerPlanner {
    static func triggers(
        snapshot: AetherListBoundaryTriggerSnapshot,
        configuration: AetherListBoundaryTriggerConfiguration
    ) -> [AetherListBoundaryTrigger] {
        guard snapshot.itemCount > 0 else {
            return []
        }
        if !configuration.triggersDuringProgrammaticScroll && !snapshot.isUserInitiated {
            return []
        }

        var result: [AetherListBoundaryTrigger] = []
        var topReasons: [AetherListBoundaryTriggerReason] = []
        if let topDistance = configuration.topDistance,
           snapshot.visibleContentOffset <= topDistance {
            topReasons.append(.distance)
        }
        if let topItemThreshold = configuration.topItemThreshold,
           let firstIndex = firstKnownIndex(in: snapshot.displayedRange),
           firstIndex <= topItemThreshold {
            topReasons.append(.itemThreshold)
        }
        if !topReasons.isEmpty {
            result.append(AetherListBoundaryTrigger(edge: .top, reasons: topReasons))
        }

        var bottomReasons: [AetherListBoundaryTriggerReason] = []
        if let bottomDistance = configuration.bottomDistance,
           snapshot.visibleBottomContentOffset <= bottomDistance {
            bottomReasons.append(.distance)
        }
        if let bottomItemThreshold = configuration.bottomItemThreshold,
           let lastIndex = lastKnownIndex(in: snapshot.displayedRange),
           lastIndex >= max(0, snapshot.itemCount - 1 - bottomItemThreshold) {
            bottomReasons.append(.itemThreshold)
        }
        if !bottomReasons.isEmpty {
            result.append(AetherListBoundaryTrigger(edge: .bottom, reasons: bottomReasons))
        }

        return result
    }

    private static func firstKnownIndex(in displayedRange: AetherListDisplayedItemRange) -> Int? {
        var indices: [Int] = []
        if let first = displayedRange.loadedRange?.lowerBound {
            indices.append(first)
        }
        if let first = displayedRange.visibleRange?.lowerBound {
            indices.append(first)
        }
        return indices.min()
    }

    private static func lastKnownIndex(in displayedRange: AetherListDisplayedItemRange) -> Int? {
        var indices: [Int] = []
        if let upperBound = displayedRange.loadedRange?.upperBound,
           upperBound > 0 {
            indices.append(upperBound - 1)
        }
        if let upperBound = displayedRange.visibleRange?.upperBound,
           upperBound > 0 {
            indices.append(upperBound - 1)
        }
        return indices.max()
    }
}

internal struct AetherListContentMetrics: Equatable {
    let itemOffsets: [CGFloat]
    let totalContentHeight: CGFloat
    let effectiveOffsetInsets: UIEdgeInsets
}

internal enum AetherListContentMetricsPlanner {
    static func metrics(
        itemHeights: [CGFloat],
        itemOffsetInsets: UIEdgeInsets?,
        virtualContentInsets: AetherListVirtualContentInsets
    ) -> AetherListContentMetrics {
        let effectiveOffsetInsets = self.effectiveOffsetInsets(
            itemOffsetInsets: itemOffsetInsets,
            virtualContentInsets: virtualContentInsets
        )
        let result = AetherListFrameMetrics.rebuildOffsets(
            heights: itemHeights.map { $0.isFinite ? max(0, $0) : 0 },
            offsetInsets: effectiveOffsetInsets
        )
        return AetherListContentMetrics(
            itemOffsets: result.offsets,
            totalContentHeight: result.totalHeight,
            effectiveOffsetInsets: effectiveOffsetInsets
        )
    }

    static func effectiveOffsetInsets(
        itemOffsetInsets: UIEdgeInsets?,
        virtualContentInsets: AetherListVirtualContentInsets
    ) -> UIEdgeInsets {
        let base = itemOffsetInsets ?? .zero
        return UIEdgeInsets(
            top: normalized(base.top) + virtualContentInsets.top,
            left: base.left,
            bottom: normalized(base.bottom) + virtualContentInsets.bottom,
            right: base.right
        )
    }

    static func topDelta(
        from oldInsets: UIEdgeInsets,
        to newInsets: UIEdgeInsets
    ) -> CGFloat {
        newInsets.top - oldInsets.top
    }

    private static func normalized(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}

internal struct AetherListEffectiveInsetsPlan: Equatable {
    let contentInset: UIEdgeInsets
    let scrollIndicatorInsets: UIEdgeInsets
    let contentOffset: CGPoint?
}

internal enum AetherListEffectiveInsetsPlanner {
    static func plan(
        baseInsets: UIEdgeInsets,
        keyboardBottomInset: CGFloat,
        explicitScrollIndicatorInsets: UIEdgeInsets?,
        stackFromBottom: Bool,
        totalContentHeight: CGFloat,
        viewportHeight: CGFloat,
        contentSizeHeight: CGFloat,
        currentContentInset: UIEdgeInsets,
        currentContentOffset: CGPoint,
        isTrackingOrDragging: Bool,
        bottomAnchorTolerance: CGFloat,
        preserveContentOffset: Bool = false,
        alwaysCompensateBottomInsetChanges: Bool = false
    ) -> AetherListEffectiveInsetsPlan {
        let contentInset = effectiveContentInset(
            baseInsets: baseInsets,
            keyboardBottomInset: keyboardBottomInset,
            stackFromBottom: stackFromBottom,
            totalContentHeight: totalContentHeight,
            viewportHeight: viewportHeight
        )
        let scrollIndicatorInsets = explicitScrollIndicatorInsets ?? contentInset
        let contentOffset = compensatedContentOffset(
            currentContentOffset: currentContentOffset,
            oldContentInset: currentContentInset,
            newContentInset: contentInset,
            viewportHeight: viewportHeight,
            contentSizeHeight: contentSizeHeight,
            isTrackingOrDragging: isTrackingOrDragging,
            bottomAnchorTolerance: bottomAnchorTolerance,
            preserveContentOffset: preserveContentOffset,
            alwaysCompensateBottomInsetChanges: alwaysCompensateBottomInsetChanges
        )
        return AetherListEffectiveInsetsPlan(
            contentInset: contentInset,
            scrollIndicatorInsets: scrollIndicatorInsets,
            contentOffset: contentOffset
        )
    }

    static func effectiveContentInset(
        baseInsets: UIEdgeInsets,
        keyboardBottomInset: CGFloat,
        stackFromBottom: Bool,
        totalContentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> UIEdgeInsets {
        var effective = baseInsets
        effective.bottom += normalized(keyboardBottomInset)
        if stackFromBottom {
            let availableHeight = normalized(viewportHeight) - effective.top - effective.bottom
            let topPadding = max(0, availableHeight - normalized(totalContentHeight))
            effective.top += topPadding
        }
        return effective
    }

    static func maxContentOffsetY(
        contentSizeHeight: CGFloat,
        viewportHeight: CGFloat,
        contentInset: UIEdgeInsets
    ) -> CGFloat {
        let minY = -contentInset.top
        let maxY = normalized(contentSizeHeight) + contentInset.bottom - normalized(viewportHeight)
        return max(minY, maxY)
    }

    private static func compensatedContentOffset(
        currentContentOffset: CGPoint,
        oldContentInset: UIEdgeInsets,
        newContentInset: UIEdgeInsets,
        viewportHeight: CGFloat,
        contentSizeHeight: CGFloat,
        isTrackingOrDragging: Bool,
        bottomAnchorTolerance: CGFloat,
        preserveContentOffset: Bool,
        alwaysCompensateBottomInsetChanges: Bool
    ) -> CGPoint? {
        guard oldContentInset != newContentInset else {
            return nil
        }
        guard !preserveContentOffset else {
            return nil
        }

        let bottomDelta = newContentInset.bottom - oldContentInset.bottom
        if alwaysCompensateBottomInsetChanges, abs(bottomDelta) > CGFloat.ulpOfOne {
            let minY = -newContentInset.top
            let maxY = maxContentOffsetY(
                contentSizeHeight: contentSizeHeight,
                viewportHeight: viewportHeight,
                contentInset: newContentInset
            )
            let targetY = max(minY, min(maxY, currentContentOffset.y + bottomDelta))
            let offset = CGPoint(x: currentContentOffset.x, y: targetY)
            return offset != currentContentOffset ? offset : nil
        }

        let oldMaxY = maxContentOffsetY(
            contentSizeHeight: contentSizeHeight,
            viewportHeight: viewportHeight,
            contentInset: oldContentInset
        )
        let newMaxY = maxContentOffsetY(
            contentSizeHeight: contentSizeHeight,
            viewportHeight: viewportHeight,
            contentInset: newContentInset
        )
        let tolerance = max(0, bottomAnchorTolerance)
        if currentContentOffset.y >= oldMaxY - tolerance {
            let anchoredOffset = CGPoint(x: currentContentOffset.x, y: newMaxY)
            return anchoredOffset != currentContentOffset ? anchoredOffset : nil
        }

        let topDelta = newContentInset.top - oldContentInset.top
        guard !isTrackingOrDragging && abs(topDelta) > CGFloat.ulpOfOne else {
            return nil
        }
        return CGPoint(x: currentContentOffset.x, y: currentContentOffset.y - topDelta)
    }

    private static func normalized(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }
}

internal struct AetherListFrameReplayRemoval<NodeID: Hashable>: Equatable {
    let nodeId: NodeID
    let animation: AetherListItemDeleteAnimation
    let hint: AetherListItemOperationDirectionHint?
}

internal enum AetherListFrameReplayCommand<NodeID: Hashable>: Equatable {
    case setFrame(nodeId: NodeID, frame: CGRect)
    case animateFrame(
        nodeId: NodeID,
        from: CGRect,
        to: CGRect,
        duration: Double,
        curve: AetherListNodeFrameReplayCurve
    )
    case insert(
        nodeId: NodeID,
        frame: CGRect,
        animation: AetherListNodeInsertionReplayAnimation
    )
    case remove(
        nodeId: NodeID,
        animation: AetherListItemDeleteAnimation?,
        hint: AetherListItemOperationDirectionHint?
    )
}

internal protocol AetherListFrameReplayCommandExecuting {
    associatedtype NodeID: Hashable
    func execute(_ command: AetherListFrameReplayCommand<NodeID>)
}

internal enum AetherListFrameReplayCommandPlanner {
    static func commands<NodeID: Hashable>(
        nodeIdsInDisplayOrder: [NodeID],
        indexByNodeId: [NodeID: Int],
        targetFrameByNodeId: [NodeID: CGRect],
        previousFrameByNodeId: [NodeID: CGRect],
        insertedNodeIds: Set<NodeID>,
        removals: [AetherListFrameReplayRemoval<NodeID>],
        replayPlan: AetherListNodeReplayPlan,
        forceItemAnimationIndices: Set<Int>,
        insertionDirectionHintByIndex: [Int: AetherListItemOperationDirectionHint],
        requestItemInsertionAnimations: Bool,
        invertOffsetDirection: Bool
    ) -> [AetherListFrameReplayCommand<NodeID>] {
        var commands: [AetherListFrameReplayCommand<NodeID>] = []

        if replayPlan.animatesStructuralChanges {
            for nodeId in nodeIdsInDisplayOrder {
                guard let index = indexByNodeId[nodeId],
                      let targetFrame = targetFrameByNodeId[nodeId] else {
                    continue
                }
                if insertedNodeIds.contains(nodeId) {
                    let insertionAnimation = replayPlan.insertionAnimation(
                        isNewNode: true,
                        forceItemAnimation: forceItemAnimationIndices.contains(index)
                            || requestItemInsertionAnimations,
                        directionHint: insertionDirectionHintByIndex[index],
                        invertOffsetDirection: invertOffsetDirection
                    )
                    commands.append(.insert(
                        nodeId: nodeId,
                        frame: targetFrame,
                        animation: insertionAnimation
                    ))
                } else if let previousFrame = previousFrameByNodeId[nodeId],
                          previousFrame != targetFrame {
                    switch replayPlan.survivingFrameAnimation {
                    case .none:
                        commands.append(.setFrame(nodeId: nodeId, frame: targetFrame))
                    case let .animated(duration, curve):
                        commands.append(.animateFrame(
                            nodeId: nodeId,
                            from: previousFrame,
                            to: targetFrame,
                            duration: duration,
                            curve: curve
                        ))
                    }
                } else {
                    commands.append(.setFrame(nodeId: nodeId, frame: targetFrame))
                }
            }

            for removal in removals {
                commands.append(.remove(
                    nodeId: removal.nodeId,
                    animation: replayPlan.deletionAnimation(for: removal.animation),
                    hint: removal.hint
                ))
            }
        } else {
            for nodeId in nodeIdsInDisplayOrder {
                guard let targetFrame = targetFrameByNodeId[nodeId] else {
                    continue
                }
                commands.append(.setFrame(nodeId: nodeId, frame: targetFrame))
            }
            for removal in removals {
                commands.append(.remove(
                    nodeId: removal.nodeId,
                    animation: nil,
                    hint: removal.hint
                ))
            }
        }

        return commands
    }
}

internal enum AetherListLayoutTransitionCurveSpec: Equatable {
    case linear
    case easeInOut
    case spring
    case customSpring(damping: CGFloat, initialVelocity: CGFloat)
    case custom(Float, Float, Float, Float)

    init(_ curve: ContainedViewLayoutTransitionCurve) {
        switch curve {
        case .linear:
            self = .linear
        case .easeInOut:
            self = .easeInOut
        case .spring:
            self = .spring
        case let .customSpring(damping, initialVelocity):
            self = .customSpring(damping: damping, initialVelocity: initialVelocity)
        case let .custom(p1, p2, p3, p4):
            self = .custom(p1, p2, p3, p4)
        }
    }

    var containedCurve: ContainedViewLayoutTransitionCurve {
        switch self {
        case .linear:
            return .linear
        case .easeInOut:
            return .easeInOut
        case .spring:
            return .spring
        case let .customSpring(damping, initialVelocity):
            return .customSpring(damping: damping, initialVelocity: initialVelocity)
        case let .custom(p1, p2, p3, p4):
            return .custom(p1, p2, p3, p4)
        }
    }
}

internal enum AetherListLayoutTransitionSpec: Equatable {
    case immediate
    case animated(duration: Double, curve: AetherListLayoutTransitionCurveSpec)

    static func make(duration: Double, curve: ContainedViewLayoutTransitionCurve) -> AetherListLayoutTransitionSpec {
        guard duration > .ulpOfOne else {
            return .immediate
        }
        return .animated(duration: duration, curve: AetherListLayoutTransitionCurveSpec(curve))
    }

    var containedTransition: ContainedViewLayoutTransition {
        switch self {
        case .immediate:
            return .immediate
        case let .animated(duration, curve):
            return .animated(duration: duration, curve: curve.containedCurve)
        }
    }
}

internal struct AetherListSizeAndInsetsUpdateCommand: Equatable {
    let targetFrame: CGRect?
    let updatedLayoutParams: AetherListItemLayoutParams?
    let headerInsets: UIEdgeInsets?
    let scrollIndicatorInsets: UIEdgeInsets?
    let itemOffsetInsets: UIEdgeInsets?
    let virtualContentInsets: AetherListVirtualContentInsets?
    let insets: UIEdgeInsets
    let transition: AetherListLayoutTransitionSpec
    let prefersCustomTransition: Bool
}

internal enum AetherListSizeAndInsetsCommand: Equatable {
    case update(AetherListSizeAndInsetsUpdateCommand)
    case forceRelayout(params: AetherListItemLayoutParams)
}

internal protocol AetherListSizeAndInsetsCommandExecuting {
    func execute(_ command: AetherListSizeAndInsetsCommand)
}

internal enum AetherListSizeAndInsetsCommandPlanner {
    static func command(
        currentFrame: CGRect,
        currentBoundsSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        currentLayoutParams: AetherListItemLayoutParams?,
        options: AetherListTransactionOptions,
        update: AetherListUpdateSizeAndInsets?
    ) -> AetherListSizeAndInsetsCommand? {
        if let update {
            let transition = AetherListLayoutTransitionSpec.make(
                duration: update.duration,
                curve: update.curve
            )
            let shouldUpdateSize = update.size.width > 0.0
                && update.size.height > 0.0
                && currentBoundsSize != update.size
            let targetFrame: CGRect?
            let updatedLayoutParams: AetherListItemLayoutParams?
            if shouldUpdateSize {
                targetFrame = CGRect(origin: currentFrame.origin, size: update.size)
                let nextParams = AetherListItemLayoutParams(
                    width: update.size.width,
                    leftInset: safeAreaInsets.left,
                    rightInset: safeAreaInsets.right,
                    availableHeight: update.size.height
                )
                updatedLayoutParams = nextParams != currentLayoutParams ? nextParams : nil
            } else {
                targetFrame = nil
                updatedLayoutParams = nil
            }

            return .update(AetherListSizeAndInsetsUpdateCommand(
                targetFrame: targetFrame,
                updatedLayoutParams: updatedLayoutParams,
                headerInsets: update.headerInsets,
                scrollIndicatorInsets: update.scrollIndicatorInsets,
                itemOffsetInsets: update.itemOffsetInsets,
                virtualContentInsets: update.virtualContentInsets,
                insets: update.insets,
                transition: transition,
                prefersCustomTransition: update.customTransition != nil
            ))
        }

        if options.contains(.forceUpdate), let currentLayoutParams {
            return .forceRelayout(params: currentLayoutParams)
        }

        return nil
    }
}

internal enum AetherListScrollAnchoringCommand: Equatable {
    case setContentOffset(CGPoint, animated: Bool)
    case adjustContentOffset(deltaY: CGFloat, animated: Bool, transition: AetherListLayoutTransitionSpec)
    case applyEffectiveInsetsAndScrollToBottom(animated: Bool)
}

internal protocol AetherListScrollAnchoringCommandExecuting {
    func execute(_ command: AetherListScrollAnchoringCommand)
}

internal enum AetherListScrollAnchoringCommandPlanner {
    static func command(
        itemCount: Int,
        scrollToItem: AetherListScrollToItem?,
        resolvedScrollToOffsetY: CGFloat?,
        additionalScrollDistance: CGFloat,
        additionalDistanceTransition: AetherListLayoutTransitionSpec,
        stationaryAnchor: AetherListIntermediateAnchor?,
        postIntermediateState: AetherListIntermediateState,
        currentContentOffset: CGPoint,
        stackFromBottom: Bool,
        wasNearBottom: Bool,
        animate: Bool,
        animateTopItemPosition: Bool
    ) -> AetherListScrollAnchoringCommand? {
        if let scrollToItem {
            guard scrollToItem.index >= 0,
                  scrollToItem.index < itemCount,
                  let resolvedScrollToOffsetY else {
                return nil
            }
            return .setContentOffset(
                CGPoint(
                    x: currentContentOffset.x,
                    y: resolvedScrollToOffsetY + additionalScrollDistance
                ),
                animated: scrollToItem.animated
            )
        }

        if !additionalScrollDistance.isZero {
            return .adjustContentOffset(
                deltaY: additionalScrollDistance,
                animated: animate,
                transition: additionalDistanceTransition
            )
        }

        if let stationaryAnchor,
           let delta = postIntermediateState.offsetDelta(preserving: stationaryAnchor) {
            guard abs(delta) > CGFloat.ulpOfOne else {
                return nil
            }
            return .setContentOffset(
                CGPoint(x: currentContentOffset.x, y: currentContentOffset.y + delta),
                animated: animateTopItemPosition && animate
            )
        }

        if stackFromBottom && wasNearBottom {
            return .applyEffectiveInsetsAndScrollToBottom(animated: animate)
        }

        return nil
    }
}

/// Immutable snapshot of the list's current state.
public struct AetherListState {
    public let itemCount: Int
    public let visibleSize: CGSize
    public let insets: UIEdgeInsets
    public let visualInsets: UIEdgeInsets
    public let headerInsets: UIEdgeInsets?
    public let scrollIndicatorInsets: UIEdgeInsets?
    public let virtualContentInsets: AetherListVirtualContentInsets
    public let totalContentHeight: CGFloat
    public let virtualOffset: CGFloat
    public let visibleRange: Range<Int>?
    public let loadedRange: Range<Int>?
    public let visibleViewCount: Int
    public let layoutCacheCount: Int
    public let reusePoolCount: Int
    public let pendingTransactionCount: Int
}

public struct AetherListDebugCounters: Equatable {
    public internal(set) var visibleViews: Int = 0
    public internal(set) var createdViews: Int = 0
    public internal(set) var reusedViews: Int = 0
    public internal(set) var recycledViews: Int = 0
    public internal(set) var layoutCacheHits: Int = 0
    public internal(set) var layoutCacheMisses: Int = 0
    public internal(set) var transactionCount: Int = 0
    public internal(set) var maxVisibleViews: Int = 0
    public internal(set) var lastTransactionDuration: TimeInterval = 0
}

/// Lightweight signpost/counter bundle for list development builds.
public final class AetherListDebugInstrumentation {
    public var isEnabled: Bool = false
    public internal(set) var counters = AetherListDebugCounters()

    private let log = OSLog(subsystem: "AetherUI", category: "AetherListView")

    public init() {}

    @discardableResult
    internal func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let signpostID = OSSignpostID(log: log)
        let start = CACurrentMediaTime()
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        let result = body()
        os_signpost(.end, log: log, name: name, signpostID: signpostID)
        counters.lastTransactionDuration = CACurrentMediaTime() - start
        return result
    }

    internal func recordVisibleViews(_ count: Int) {
        counters.visibleViews = count
        counters.maxVisibleViews = max(counters.maxVisibleViews, count)
    }

    internal func recordCreatedView() {
        counters.createdViews += 1
    }

    internal func recordReusedView() {
        counters.reusedViews += 1
    }

    internal func recordRecycledView() {
        counters.recycledViews += 1
    }

    internal func recordLayoutCacheHit() {
        counters.layoutCacheHits += 1
    }

    internal func recordLayoutCacheMiss() {
        counters.layoutCacheMisses += 1
    }

    internal func recordTransaction() {
        counters.transactionCount += 1
    }
}

/// Small CADisplayLink scheduler. It coalesces submitted blocks and drains
/// them on the next VSync without retaining the target list view.
public final class AetherListDisplayLinkDriver {
    private final class Target: NSObject {
        weak var owner: AetherListDisplayLinkDriver?

        init(owner: AetherListDisplayLinkDriver) {
            self.owner = owner
        }

        @objc func tick(_ link: CADisplayLink) {
            owner?.tick(link)
        }
    }

    private lazy var target = Target(owner: self)
    private var displayLink: CADisplayLink?
    private var callbacks: [() -> Void] = []

    public init() {}

    deinit {
        displayLink?.invalidate()
    }

    public func schedule(_ callback: @escaping () -> Void) {
        callbacks.append(callback)
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func tick(_ link: CADisplayLink) {
        let current = callbacks
        callbacks.removeAll()
        link.invalidate()
        displayLink = nil
        current.forEach { $0() }
    }
}

internal enum AetherListFrameMetrics {
    static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        return CGRect(
            x: pixelAligned(rect.origin.x, scale: scale),
            y: pixelAligned(rect.origin.y, scale: scale),
            width: pixelAligned(rect.size.width, scale: scale),
            height: pixelAligned(rect.size.height, scale: scale)
        )
    }

    static func rebuildOffsets(heights: [CGFloat], offsetInsets: UIEdgeInsets) -> (offsets: [CGFloat], totalHeight: CGFloat) {
        var offsets: [CGFloat] = []
        offsets.reserveCapacity(heights.count)
        var y = offsetInsets.top
        for height in heights {
            offsets.append(y)
            y += height
        }
        return (offsets, y + offsetInsets.bottom)
    }

    static func scrollBounds(
        contentSizeHeight: CGFloat,
        viewportHeight: CGFloat,
        contentInset: UIEdgeInsets
    ) -> (minY: CGFloat, maxY: CGFloat, scrollableDistance: CGFloat) {
        let minY = -contentInset.top
        let maxY = max(minY, contentSizeHeight + contentInset.bottom - viewportHeight)
        return (minY, maxY, max(0, maxY - minY))
    }

    static func pagedScrollToTopOffset(
        currentOffsetY: CGFloat,
        contentSizeHeight: CGFloat,
        viewportHeight: CGFloat,
        contentInset: UIEdgeInsets,
        distance: CGFloat? = nil
    ) -> CGFloat? {
        let bounds = scrollBounds(
            contentSizeHeight: contentSizeHeight,
            viewportHeight: viewportHeight,
            contentInset: contentInset
        )
        guard bounds.scrollableDistance > CGFloat.ulpOfOne,
              currentOffsetY > bounds.minY + 0.5 else {
            return nil
        }

        let visiblePageHeight = viewportHeight - contentInset.top - contentInset.bottom
        let defaultDistance = visiblePageHeight * 2.0
        let pageDistance = max(1.0, distance ?? defaultDistance)
        let clampedCurrentY = min(bounds.maxY, max(bounds.minY, currentOffsetY))
        let targetY = max(bounds.minY, clampedCurrentY - pageDistance)
        guard targetY < currentOffsetY - 0.5 else {
            return nil
        }
        return targetY
    }

    static func overscrollDistances(
        contentOffsetY: CGFloat,
        contentSizeHeight: CGFloat,
        viewportHeight: CGFloat,
        contentInset: UIEdgeInsets
    ) -> (top: CGFloat, bottom: CGFloat) {
        let bounds = scrollBounds(
            contentSizeHeight: contentSizeHeight,
            viewportHeight: viewportHeight,
            contentInset: contentInset
        )
        return (
            top: max(0, bounds.minY - contentOffsetY),
            bottom: max(0, contentOffsetY - bounds.maxY)
        )
    }

    static func verticalScrollIndicatorFrame(
        boundsWidth: CGFloat,
        viewportHeight: CGFloat,
        contentSizeHeight: CGFloat,
        contentInset: UIEdgeInsets,
        scrollIndicatorInsets: UIEdgeInsets?,
        contentOffsetY: CGFloat,
        followsOverscroll: Bool,
        indicatorWidth: CGFloat = 3,
        rightInset: CGFloat = 5,
        minimumThumbHeight: CGFloat = 24
    ) -> CGRect? {
        let scrollBounds = scrollBounds(
            contentSizeHeight: contentSizeHeight,
            viewportHeight: viewportHeight,
            contentInset: contentInset
        )
        guard scrollBounds.scrollableDistance > 1 else {
            return nil
        }

        let trackInsets = scrollIndicatorInsets ?? contentInset
        let trackTop = trackInsets.top
        let trackBottom = viewportHeight - trackInsets.bottom
        let trackHeight = trackBottom - trackTop
        guard trackHeight > 1 else {
            return nil
        }

        let scrollExtent = max(viewportHeight + scrollBounds.scrollableDistance, 1)
        let thumbHeight = min(
            trackHeight,
            max(minimumThumbHeight, trackHeight * min(1, viewportHeight / scrollExtent))
        )
        let rawProgress = (contentOffsetY - scrollBounds.minY) / max(scrollBounds.scrollableDistance, 1)
        let progress = followsOverscroll ? rawProgress : min(1, max(0, rawProgress))
        let y = trackTop + (trackHeight - thumbHeight) * progress
        return CGRect(
            x: boundsWidth - rightInset,
            y: y,
            width: indicatorWidth,
            height: thumbHeight
        )
    }

    static func visibleRange(
        offsets: [CGFloat],
        heights: [CGFloat],
        viewportTop: CGFloat,
        viewportHeight: CGFloat,
        preloadPages: CGFloat
    ) -> Range<Int> {
        guard !offsets.isEmpty, offsets.count == heights.count else { return 0..<0 }

        let preload = max(0, preloadPages) * viewportHeight
        let top = viewportTop - preload
        let bottom = viewportTop + viewportHeight + preload

        var lo = 0
        var hi = offsets.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let itemBottom = offsets[mid] + heights[mid]
            if itemBottom < top {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        let first = max(0, lo)

        lo = first
        hi = offsets.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let itemTop = offsets[mid]
            if itemTop > bottom {
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        let last = min(offsets.count - 1, hi)
        guard first <= last else { return first..<first }
        return first..<(last + 1)
    }

    static func scrollOffset(
        index: Int,
        position: AetherListScrollPosition,
        offsets: [CGFloat],
        heights: [CGFloat],
        nodeInsets: UIEdgeInsets,
        viewportHeight: CGFloat,
        insets: UIEdgeInsets,
        currentOffset: CGFloat,
        customOverflow: CGFloat?
    ) -> CGFloat {
        guard index >= 0, index < offsets.count, index < heights.count else { return 0 }

        let itemTop = offsets[index] + nodeInsets.top
        let itemHeight = max(0, heights[index] - nodeInsets.top - nodeInsets.bottom)
        let itemBottom = itemTop + itemHeight

        switch position {
        case .visible:
            let visibleTop = currentOffset + insets.top
            let visibleBottom = currentOffset + viewportHeight - insets.bottom
            if itemTop >= visibleTop && itemBottom <= visibleBottom {
                return currentOffset
            }
            if itemTop < visibleTop {
                return itemTop - insets.top
            }
            return itemBottom - viewportHeight + insets.bottom

        case .top(let offset):
            return itemTop - insets.top - offset

        case .bottom(let offset):
            return itemBottom - viewportHeight + insets.bottom + offset

        case .center:
            return itemTop + itemHeight / 2 - viewportHeight / 2

        case .centerWithOverflow(let overflow):
            let contentAreaHeight = viewportHeight - insets.top - insets.bottom
            if itemHeight <= contentAreaHeight + CGFloat.ulpOfOne {
                return itemTop + itemHeight / 2 - viewportHeight / 2
            }
            switch overflow {
            case .top:
                return itemTop - insets.top
            case .bottom:
                return itemBottom - viewportHeight + insets.bottom
            case .custom:
                return customOverflow.map { itemBottom - viewportHeight + insets.bottom + $0 } ?? (itemTop - insets.top)
            }
        }
    }

    static func deletionRemap(itemCount: Int, deletedIndices: [Int]) -> [Int: Int] {
        let deletes = Set(deletedIndices)
        var remap: [Int: Int] = [:]
        var removedBefore = 0
        for index in 0..<itemCount {
            if deletes.contains(index) {
                removedBefore += 1
            } else if removedBefore > 0 {
                remap[index] = index - removedBefore
            }
        }
        return remap
    }

    static func insertionRemap(survivingIndices: [Int], insertedIndices: [Int]) -> [Int: Int] {
        let sortedInserts = insertedIndices.sorted()
        var remap: [Int: Int] = [:]
        for index in survivingIndices {
            var offset = 0
            for insert in sortedInserts {
                if insert <= index + offset {
                    offset += 1
                }
            }
            if offset != 0 {
                remap[index] = index + offset
            }
        }
        return remap
    }
}
