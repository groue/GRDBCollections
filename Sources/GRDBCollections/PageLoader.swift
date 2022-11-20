@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
enum PaginationAction {
    case refresh
    case fetchNextPage
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
actor PageLoader<DataSource: PaginationDataSource> {
    typealias Element = DataSource.Element
    typealias PageID = DataSource.PageID
    
    private enum PageState {
        case loading(Task<Void, Error>)
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
    
    private let willPerform: (_ action: PaginationAction) async -> Void
    private let didPerform: (_ action: PaginationAction, _ newElements: [Element], _ nextPage: AnyHashable?) async -> Void
    
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
        willPerform: @escaping (_ action: PaginationAction) async -> Void,
        didPerform: @escaping (_ action: PaginationAction, _ newElements: [Element], _ nextPage: AnyHashable?) async -> Void)
    {
        self.dataSource = dataSource
        self.willPerform = willPerform
        self.didPerform = didPerform
    }
    
    private func perform(action: PaginationAction) async throws {
        if action == .refresh {
            for pageState in pageStates.values {
                pageState.cancel()
            }
            pageStates = [:]
        }
        
        let pageIdentifier: PageID
        switch action {
        case .refresh:
            pageIdentifier = dataSource.firstPageIdentifier
        case .fetchNextPage:
            // If last page was loaded, `nextPageIdentifier` is nil.
            // But we won't try to fetch the first page again.
            // The check for `pageStates[pageIdentifier]` below will notice
            // that the first page was already loaded, so that we
            // exit early.
            pageIdentifier = nextPageIdentifier ?? dataSource.firstPageIdentifier
        }
        
        if pageStates[pageIdentifier] != nil {
            // Already loaded or loading
            return
        }
        
        let task = Task {
            do {
                try Task.checkCancellation()
                await willPerform(action)
                let page = try await dataSource.page(at: pageIdentifier)
                try Task.checkCancellation()
                pageStates[pageIdentifier] = .loaded
                nextPageIdentifier = page.nextPageIdentifier
                await didPerform(action, page.elements, page.nextPageIdentifier)
            } catch is CancellationError {
            } catch {
                pageStates.removeValue(forKey: pageIdentifier)
                throw error
            }
        }
        pageStates[pageIdentifier] = .loading(task)
        return try await task.value
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PageLoader: PageLoaderProtocol {
    func fetchNextPage() async throws {
        try await perform(action: .fetchNextPage)
    }
    
    func refresh() async throws {
        try await perform(action: .refresh)
    }
    
    func fetchNextPageIfIdle() async throws {
        if isLoading { return }
        try await fetchNextPage()
    }
}
