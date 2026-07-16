import yoga

extension LoomJustify {
    var yogaValue: YGJustify {
        switch self {
        case .start: return .flexStart
        case .center: return .center
        case .end: return .flexEnd
        case .spaceBetween: return .spaceBetween
        case .spaceAround: return .spaceAround
        case .spaceEvenly: return .spaceEvenly
        }
    }
}

extension LoomAlign {
    var yogaValue: YGAlign {
        switch self {
        case .start: return .flexStart
        case .center: return .center
        case .end: return .flexEnd
        case .stretch: return .stretch
        case .baseline: return .baseline
        }
    }
}

extension LoomWrap {
    var yogaValue: YGWrap {
        switch self {
        case .noWrap: return .noWrap
        case .wrap: return .wrap
        case .wrapReverse: return .wrapReverse
        }
    }
}

extension LoomDirection {
    var yogaValue: YGDirection {
        switch self {
        case .ltr: return .LTR
        case .rtl: return .RTL
        case .inherit: return .inherit
        }
    }
}
