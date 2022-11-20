import Collections

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedCollection<Element, ID: Hashable> {
    private var dictionary: OrderedDictionary<ID, Element>
    private var idKeyPath: KeyPath<Element, ID>
    var makePrefetch: (_ index: Int, _ elementCount: Int) -> (() -> Void)?
    
    init(
        id: KeyPath<Element, ID>,
        makePrefetch: @escaping (_ index: Int, _ elementCount: Int) -> (() -> Void)?)
    {
        self.dictionary = [:]
        self.idKeyPath = id
        self.makePrefetch = makePrefetch
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedCollection {
    mutating func removeAll() {
        dictionary.removeAll()
    }
    
    mutating func append(
        page newElements: [Element],
        with strategy: PaginationMergeStrategy<Element, ID>)
    {
        switch strategy {
        case .deleteAndAppend:
            for element in newElements {
                dictionary.removeValue(forKey: element[keyPath: idKeyPath])
            }
            let appendedElements = newElements.lazy.map { [idKeyPath] in ($0[keyPath: idKeyPath], $0) }
            dictionary.merge(appendedElements, uniquingKeysWith: { (_, new) in new })
            
        case .updateOrAppend:
            let appendedElements = newElements.lazy.map { [idKeyPath] in ($0[keyPath: idKeyPath], $0) }
            dictionary.merge(appendedElements, uniquingKeysWith: { (_, new) in new })
            
        case .ignoreOrAppend:
            let appendedElements = newElements.lazy.map { [idKeyPath] in ($0[keyPath: idKeyPath], $0) }
            dictionary.merge(appendedElements, uniquingKeysWith: { (old, _) in old })
            
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
    
    public subscript(position: Int) -> PaginatedElement<Element, ID> {
        PaginatedElement(
            idKeyPath: idKeyPath,
            element: dictionary.values[position],
            prefetch: makePrefetch(position, dictionary.count))
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedElement<Element, ID: Hashable>: Identifiable {
    let idKeyPath: KeyPath<Element, ID>
    public let element: Element
    let prefetch: (() -> Void)?
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedElement: Identifiable {
    public var id: ID { element[keyPath: idKeyPath] }
}
