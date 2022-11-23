import Collections

/// The collection of elements in a `PaginatedResults`.
///
/// ## Topics
///
/// ### Accessing the Paginated Elements
///
/// - ``subscript(_:)-5hy1n``
/// - ``PaginatedElement``
///
/// ### Accessing the Raw Elements
///
/// - ``dictionary``
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedCollection<Element, ID: Hashable> {
    /// The ordered elements, keyed by id.
    public private(set) var dictionary: OrderedDictionary<ID, Element>
    private var idKeyPath: KeyPath<Element, ID>
    private var prefetchDistance: Int
    private var appendStrategy: PaginationAppendStrategy<Element, ID>
    
    init(
        id: KeyPath<Element, ID>,
        prefetchDistance: Int,
        appendStrategy: PaginationAppendStrategy<Element, ID>)
    {
        self.dictionary = [:]
        self.idKeyPath = id
        self.prefetchDistance = prefetchDistance
        self.appendStrategy = appendStrategy
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedCollection {
    mutating func removeAll() {
        dictionary.removeAll()
    }
    
    mutating func append(page newElements: [Element]) {
        switch appendStrategy {
        case .removeAndAppend:
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
    
    /// Accesses the element at the specified position.
    public subscript(position: Int) -> PaginatedElement<Element, ID> {
        let value = dictionary.values[position]
        let needsPrefetch = (count - position) <= prefetchDistance
        return PaginatedElement(
            id: value[keyPath: idKeyPath],
            value: value,
            needsPrefetchOnAppear: needsPrefetch)
    }
}

/// A paginated element.
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedElement<Element, ID: Hashable>: Identifiable {
    /// The identity of the value.
    public let id: ID
    
    /// The value.
    public let value: Element
    
    /// A boolean value indicating whether a new page should be prefetched when
    /// this element appears on screen.
    public var needsPrefetchOnAppear: Bool
}
