import Collections

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedCollection<Element: Identifiable> {
    private var dictionary: OrderedDictionary<Element.ID, Element>
    var makePrefetch: (_ index: Int, _ elementCount: Int) -> (() -> Void)?
    
    init(makePrefetch: @escaping (_ index: Int, _ elementCount: Int) -> (() -> Void)?) {
        self.dictionary = [:]
        self.makePrefetch = makePrefetch
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedCollection {
    mutating func removeAll() {
        dictionary.removeAll()
    }
    
    mutating func append(page newElements: [Element], with strategy: PaginationMergeStrategy<Element>) {
        switch strategy {
        case .deleteAndAppend:
            for element in newElements {
                dictionary.removeValue(forKey: element.id)
            }
            let appendedElements = newElements.lazy.map { ($0.id, $0) }
            dictionary.merge(appendedElements, uniquingKeysWith: { (_, new) in new })
            
        case .updateOrAppend:
            let appendedElements = newElements.lazy.map { ($0.id, $0) }
            dictionary.merge(appendedElements, uniquingKeysWith: { (_, new) in new })
            
        case .ignoreOrAppend:
            let appendedElements = newElements.lazy.map { ($0.id, $0) }
            dictionary.merge(appendedElements, uniquingKeysWith: { (old, new) in old })
            
        case let .custom(append):
            append(newElements, &dictionary)
        }
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedCollection: RandomAccessCollection {
    public var count: Int { dictionary.values.count }
    public var startIndex: Int { dictionary.values.startIndex }
    public var endIndex: Int { dictionary.values.endIndex }
    
    public subscript(position: Int) -> PaginatedElement<Element> {
        PaginatedElement(
            element: dictionary.values[position],
            prefetch: makePrefetch(position, dictionary.count))
    }
}
