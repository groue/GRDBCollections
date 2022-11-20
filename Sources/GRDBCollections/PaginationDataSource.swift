public protocol PaginationDataSource<Element> {
    associatedtype Element
    associatedtype PageID: Hashable
    
    var firstPageIdentifier: PageID { get }
    func page(at pageIdentifier: PageID) async throws -> Page<Element, PageID>
}

public struct Page<Element, PageID> {
    var elements: [Element]
    var nextPageIdentifier: PageID?
    
    public init(elements: [Element], nextPageIdentifier: PageID? = nil) {
        self.elements = elements
        self.nextPageIdentifier = nextPageIdentifier
    }
}
