@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct PaginatedCollection<Element> {
    var makePrefetch: (_ index: Int, _ elementCount: Int) -> (() -> Void)?
    var elements: [Element]
    
    init(
        elements: [Element],
        makePrefetch: @escaping (_ index: Int, _ elementCount: Int) -> (() -> Void)?)
    {
        self.elements = elements
        self.makePrefetch = makePrefetch
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension PaginatedCollection {
    mutating func removeAll() {
        elements.removeAll()
    }
    
    mutating func append<S>(contentsOf newElements: S) where S: Sequence, Element == S.Element {
        elements.append(contentsOf: newElements)
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension PaginatedCollection: RandomAccessCollection {
    public var count: Int { elements.count }
    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public func index(after i: Int) -> Int { i + 1 }
    
    public subscript(position: Int) -> PaginatedElement<Element> {
        PaginatedElement(
            element: elements[position],
            prefetch: makePrefetch(position, elements.count))
    }
}
