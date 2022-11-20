@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
enum PaginationAction {
    case refresh
    case fetchNextPage
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
actor PageLoader<DataSource: PaginationDataSource> {
    typealias Element = DataSource.Element
    typealias PageID = DataSource.PageID
    
    private typealias LoadingTask = Task<Page<Element, AnyHashable>?, Error>
    
    private enum PageState {
        case loading(LoadingTask)
        case loaded
        
        func cancel() {
            switch self {
            case .loaded:
                break
            case let .loading(task):
                task.cancel()
            }
        }
    }
    
    let dataSource: DataSource
    
    private let willFetchNextPage: () async -> Void

    private var nextPageIdentifier: PageID?
    private var pageStates: [PageID: PageState] = [:]
    
    private var isLoading: Bool {
        pageStates.values.contains {
            if case .loading = $0 { return true }
            return false
        }
    }
    
    init(
        dataSource: DataSource,
        willFetchNextPage: @escaping () async -> Void)
    {
        self.dataSource = dataSource
        self.willFetchNextPage = willFetchNextPage
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PageLoader: PageLoaderProtocol {
    func fetchNextPage() async throws -> Page<Element, AnyHashable>? {
        let pageIdentifier = nextPageIdentifier ?? dataSource.firstPageIdentifier
        
        if pageStates[pageIdentifier] != nil {
            // Already loaded or loading
            return nil
        }
        
        let task: LoadingTask = Task {
            do {
                try Task.checkCancellation()
                await willFetchNextPage()
                let page = try await dataSource.page(at: pageIdentifier)
                try Task.checkCancellation()
                pageStates[pageIdentifier] = .loaded
                nextPageIdentifier = page.nextPageIdentifier
                return Page(elements: page.elements, nextPageIdentifier: page.nextPageIdentifier)
            } catch is CancellationError {
                return nil
            } catch {
                pageStates.removeValue(forKey: pageIdentifier)
                throw error
            }
        }
        pageStates[pageIdentifier] = .loading(task)
        return try await task.value
    }
    
    func refresh() async throws -> Page<Element, AnyHashable>? {
        for pageState in pageStates.values {
            pageState.cancel()
        }
        pageStates = [:]
        
        let pageIdentifier = dataSource.firstPageIdentifier
        
        let task: LoadingTask = Task {
            do {
                try Task.checkCancellation()
                let page = try await dataSource.page(at: pageIdentifier)
                try Task.checkCancellation()
                pageStates[pageIdentifier] = .loaded
                nextPageIdentifier = page.nextPageIdentifier
                return Page(elements: page.elements, nextPageIdentifier: page.nextPageIdentifier)
            } catch is CancellationError {
                return nil
            } catch {
                pageStates.removeValue(forKey: pageIdentifier)
                throw error
            }
        }
        pageStates[pageIdentifier] = .loading(task)
        return try await task.value
    }
    
    func fetchNextPageIfIdle() async throws -> Page<Element, AnyHashable>? {
        if isLoading { return nil }
        return try await fetchNextPage()
    }
}
