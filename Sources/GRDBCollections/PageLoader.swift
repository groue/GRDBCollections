@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
actor PageLoader<DataSource: PaginationDataSource> {
    typealias Element = DataSource.Element
    typealias PageID = DataSource.PageID
    
    private typealias LoadingTask = Task<Page<Element, PageID>, Error>
    
    let dataSource: DataSource
    private var nextPageIdentifier: PageID?
    private var loadingTask: LoadingTask?
    
    init(dataSource: DataSource) {
        self.dataSource = dataSource
    }
    
    private func fetchPage(at pageId: PageID) async throws -> Page<Element, PageID> {
        let page = try await dataSource.page(at: pageId)
        nextPageIdentifier = page.nextPageIdentifier
        return page
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PageLoader: PageLoaderProtocol {
    func fetchNextPage() async throws -> Page<Element, AnyHashable> {
        let page = try await fetchPage(at: nextPageIdentifier ?? dataSource.firstPageIdentifier)
        return Page(elements: page.elements, nextPageIdentifier: page.nextPageIdentifier)
    }
    
    func refresh() async throws -> Page<Element, AnyHashable> {
        let page = try await fetchPage(at: dataSource.firstPageIdentifier)
        return Page(elements: page.elements, nextPageIdentifier: page.nextPageIdentifier)
    }
}
