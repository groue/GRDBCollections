typealias Page<Element> = (elements: [Element], hasNextPage: Bool)

/// A type that hides the PageID of a ``PageSource``.
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
protocol PageLoaderProtocol<Element> {
    associatedtype Element
    func refresh() async throws -> Page<Element>
    func fetchNextPage() async throws -> Page<Element>
}

/// The actor that schedules page fetches.
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
actor PageLoader<Source: PageSource> {
    typealias Element = Source.Element
    
    let pageSource: Source
    private var nextPageIdentifier: Source.PageID?
    
    init(_ pageSource: Source) {
        self.pageSource = pageSource
    }
    
    private func fetchPage(at pageId: Source.PageID?) async throws -> Page<Element> {
        guard let pageId = pageId else {
            self.nextPageIdentifier = nil
            return (elements: [], hasNextPage: false)
        }
        
        let (elements, nextPageIdentifier) = try await pageSource.page(at: pageId)
        self.nextPageIdentifier = nextPageIdentifier
        return (elements: elements, hasNextPage: nextPageIdentifier != nil)
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PageLoader: PageLoaderProtocol {
    func fetchNextPage() async throws -> Page<Element> {
        try await fetchPage(at: nextPageIdentifier ?? pageSource.firstPageIdentifier)
    }
    
    func refresh() async throws -> Page<Element> {
        try await fetchPage(at: pageSource.firstPageIdentifier)
    }
}
