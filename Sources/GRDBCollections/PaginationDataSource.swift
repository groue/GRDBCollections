@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public protocol PaginationDataSource<Element> {
    associatedtype Element
    associatedtype PageID: Hashable
    
    var firstPageIdentifier: PageID { get }
    func page(at pageIdentifier: PageID) async throws -> Page<Element, PageID>
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct Page<Element, PageID> {
    var elements: [Element]
    var nextPageIdentifier: PageID?
    
    public init(elements: [Element], nextPageIdentifier: PageID?) {
        self.elements = elements
        self.nextPageIdentifier = nextPageIdentifier
    }
}
