import Collections

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public enum PaginationMergeStrategy<Element: Identifiable> {
    case deleteAndAppend
    case updateOrAppend
    case ignoreOrAppend
    case custom(([Element], inout OrderedDictionary<Element.ID, Element>) -> ())
}
