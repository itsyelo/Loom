import CoreGraphics
import yoga

final class YogaNode {
    let ref: YGNodeRef
    private var children: [YogaNode] = []
    private var measureClosure: ((Float, YGMeasureMode, Float, YGMeasureMode) -> CGSize)?

    init(config: YogaConfig? = nil) {
        if let config {
            ref = YGNodeNewWithConfig(config.ref)
        } else {
            ref = YGNodeNew()
        }
    }

    deinit {
        // Only free this node; children are freed by their own deinit
        // Clear context to avoid dangling pointer
        YGNodeSetMeasureFunc(ref, nil)
        YGNodeSetContext(ref, nil)
        YGNodeRemoveAllChildren(ref)
        YGNodeFree(ref)
    }

    // MARK: - Children

    func addChild(_ child: YogaNode) {
        let index = children.count
        children.append(child)
        YGNodeInsertChild(ref, child.ref, index)
    }

    // MARK: - Measure Function

    func setMeasureFunc(_ closure: @escaping (Float, YGMeasureMode, Float, YGMeasureMode) -> CGSize) {
        measureClosure = closure
        // Store unretained pointer to self — safe because self owns the YGNode
        // and will outlive it
        YGNodeSetContext(ref, Unmanaged.passUnretained(self).toOpaque())
        YGNodeSetMeasureFunc(ref, yogaMeasureCallback)
    }

    // MARK: - Calculate

    func calculateLayout(width: Float, height: Float, direction: YGDirection = .LTR) {
        YGNodeCalculateLayout(ref, width, height, direction)
    }

    // MARK: - Layout Results

    var layoutLeft: CGFloat { CGFloat(YGNodeLayoutGetLeft(ref)) }
    var layoutTop: CGFloat { CGFloat(YGNodeLayoutGetTop(ref)) }
    var layoutWidth: CGFloat { CGFloat(YGNodeLayoutGetWidth(ref)) }
    var layoutHeight: CGFloat { CGFloat(YGNodeLayoutGetHeight(ref)) }

    var layoutFrame: CGRect {
        CGRect(x: layoutLeft, y: layoutTop, width: layoutWidth, height: layoutHeight)
    }

    var layoutSize: CGSize {
        CGSize(width: layoutWidth, height: layoutHeight)
    }

    // MARK: - Style Setters: Flex Direction

    func setFlexDirection(_ direction: YGFlexDirection) {
        YGNodeStyleSetFlexDirection(ref, direction)
    }

    // MARK: - Style Setters: Alignment

    func setJustifyContent(_ justify: YGJustify) {
        YGNodeStyleSetJustifyContent(ref, justify)
    }

    func setAlignItems(_ align: YGAlign) {
        YGNodeStyleSetAlignItems(ref, align)
    }

    func setAlignContent(_ align: YGAlign) {
        YGNodeStyleSetAlignContent(ref, align)
    }

    func setAlignSelf(_ align: YGAlign) {
        YGNodeStyleSetAlignSelf(ref, align)
    }

    // MARK: - Style Setters: Flex Properties

    func setFlexGrow(_ value: Float) {
        YGNodeStyleSetFlexGrow(ref, value)
    }

    func setFlexShrink(_ value: Float) {
        YGNodeStyleSetFlexShrink(ref, value)
    }

    func setFlexBasis(_ value: Float) {
        YGNodeStyleSetFlexBasis(ref, value)
    }

    func setFlexBasisAuto() {
        YGNodeStyleSetFlexBasisAuto(ref)
    }

    // MARK: - Style Setters: Dimensions

    func setWidth(_ value: Float) { YGNodeStyleSetWidth(ref, value) }
    func setWidthAuto() { YGNodeStyleSetWidthAuto(ref) }
    func setHeight(_ value: Float) { YGNodeStyleSetHeight(ref, value) }
    func setHeightAuto() { YGNodeStyleSetHeightAuto(ref) }
    func setMinWidth(_ value: Float) { YGNodeStyleSetMinWidth(ref, value) }
    func setMaxWidth(_ value: Float) { YGNodeStyleSetMaxWidth(ref, value) }
    func setMinHeight(_ value: Float) { YGNodeStyleSetMinHeight(ref, value) }
    func setMaxHeight(_ value: Float) { YGNodeStyleSetMaxHeight(ref, value) }
    func setAspectRatio(_ value: Float) { YGNodeStyleSetAspectRatio(ref, value) }

    // MARK: - Style Setters: Spacing

    func setPadding(_ edge: YGEdge, _ value: Float) {
        YGNodeStyleSetPadding(ref, edge, value)
    }

    func setMargin(_ edge: YGEdge, _ value: Float) {
        YGNodeStyleSetMargin(ref, edge, value)
    }

    func setGap(_ gutter: YGGutter, _ value: Float) {
        YGNodeStyleSetGap(ref, gutter, value)
    }

    // MARK: - Style Setters: Wrap & Position

    func setFlexWrap(_ wrap: YGWrap) {
        YGNodeStyleSetFlexWrap(ref, wrap)
    }

    func setPositionType(_ type: YGPositionType) {
        YGNodeStyleSetPositionType(ref, type)
    }

    func setPosition(_ edge: YGEdge, _ value: Float) {
        YGNodeStyleSetPosition(ref, edge, value)
    }

    // MARK: - Style Setters: Direction

    func setDirection(_ direction: YGDirection) {
        YGNodeStyleSetDirection(ref, direction)
    }

    // MARK: - Internal: Measure Callback Bridge

    fileprivate func invokeMeasure(
        width: Float, widthMode: YGMeasureMode,
        height: Float, heightMode: YGMeasureMode
    ) -> YGSize {
        guard let closure = measureClosure else {
            return YGSize(width: 0, height: 0)
        }
        let size = closure(width, widthMode, height, heightMode)
        return YGSize(width: Float(size.width), height: Float(size.height))
    }
}

// MARK: - C Callback

private func yogaMeasureCallback(
    _ nodeRef: YGNodeConstRef?,
    _ width: Float,
    _ widthMode: YGMeasureMode,
    _ height: Float,
    _ heightMode: YGMeasureMode
) -> YGSize {
    guard let nodeRef,
          let context = YGNodeGetContext(nodeRef) else {
        return YGSize(width: 0, height: 0)
    }
    let yogaNode = Unmanaged<YogaNode>.fromOpaque(context).takeUnretainedValue()
    return yogaNode.invokeMeasure(width: width, widthMode: widthMode,
                                  height: height, heightMode: heightMode)
}
