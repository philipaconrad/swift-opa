#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

extension RegoNumber: Comparable {
    public static func < (lhs: RegoNumber, rhs: RegoNumber) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.int(let lVal), .int(let rVal)):
            return lVal < rVal
        default:
            return lhs.decimalValue < rhs.decimalValue
        }
    }
}
