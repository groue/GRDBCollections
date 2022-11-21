import Combine
import os.log

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
@MainActor
public class PaginatedResults<Element, ID: Hashable>: ObservableObject {
    @Published private var _elements: PaginatedCollection<Element, ID>!
    @Published public private(set) var state = PaginationState.notCompleted
    @Published public private(set) var error: PaginationError?
    @Published private var loadingTask: Task<Page<Element, AnyHashable>, any Error>?
    
    public var elements: PaginatedCollection<Element, ID> { _elements }
    public var isLoadingPage: Bool { loadingTask != nil }
    public let mergeStrategy: PaginationMergeStrategy<Element, ID>
    
    private let idKeyPath: KeyPath<Element, ID>
    private let prefetchStrategy: any PaginationPrefetchStrategy
    private var loader: any PageLoaderProtocol<Element>
    
    public init(
        initialElements: [Element] = [],
        id: KeyPath<Element, ID>,
        dataSource: some PaginationDataSource<Element>,
        prefetchStrategy: some PaginationPrefetchStrategy,
        mergeStrategy: PaginationMergeStrategy<Element, ID> = .updateOrAppend)
    {
        self.idKeyPath = id
        self.prefetchStrategy = prefetchStrategy
        self.mergeStrategy = mergeStrategy
        self.loader = PageLoader(dataSource: dataSource)
        
        self._elements = PaginatedCollection(id: id, makePrefetch: { [prefetchStrategy] index, elementCount in
            guard prefetchStrategy._needsPrefetchOnElementAppear(atIndex: index, elementCount: elementCount) else {
                return nil
            }
            return {
                Task { [weak self] in
                    await self?.fetchNextPageIfIdle()
                }
            }
        })
        
        _elements.append(page: initialElements, with: mergeStrategy)
        
        if prefetchStrategy._needsInitialPrefetch() {
            Task {
                await fetchNextPageIfIdle()
            }
        }
    }
    
    public convenience init(
        initialElements: [Element] = [],
        dataSource: some PaginationDataSource<Element>,
        prefetchStrategy: some PaginationPrefetchStrategy,
        mergeStrategy: PaginationMergeStrategy<Element, Element.ID> = .updateOrAppend)
    where Element: Identifiable, ID == Element.ID
    {
        self.init(
            initialElements: initialElements,
            id: \.id,
            dataSource: dataSource,
            prefetchStrategy: prefetchStrategy,
            mergeStrategy: mergeStrategy)
    }
    
    public func fetchNextPage() async throws {
        loadingTask?.cancel()
        
        let previousState = state
        let task = Task {
            try await loader.fetchNextPage()
        }
        loadingTask = task
        state = .loadingNextPage
        
        do {
            let page = try await task.value
            if loadingTask == task {
                error = nil
                loadingTask = nil
                pageDidLoad(page)
            }
        } catch is CancellationError {
        } catch {
            if loadingTask == task {
                loadingTask = nil
                state = previousState
                self.error = .fetchNextPage(error)
                throw error
            }
        }
    }
    
    public func refresh() async throws {
        loadingTask?.cancel()
        
        let previousState = state
        let task = Task {
            try await loader.refresh()
        }
        loadingTask = task
        
        do {
            let page = try await task.value
            if loadingTask == task {
                loadingTask = nil
                error = nil
                _elements.removeAll()
                pageDidLoad(page)
            }
        } catch is CancellationError {
        } catch {
            if loadingTask == task {
                loadingTask = nil
                state = previousState
                self.error = .refresh(error)
                throw error
            }
        }
    }
    
    public func removeAllAndRefresh() async throws {
        loadingTask?.cancel()
        
        let task = Task {
            try await loader.refresh()
        }
        loadingTask = task
        _elements.removeAll()
        error = nil
        state = .loadingNextPage
        
        do {
            let page = try await task.value
            if loadingTask == task {
                loadingTask = nil
                error = nil
                _elements.removeAll()
                pageDidLoad(page)
            }
        } catch is CancellationError {
        } catch {
            if loadingTask == task {
                loadingTask = nil
                state = .notCompleted
                self.error = .refresh(error)
                throw error
            }
        }
    }
    
    public func retry(from error: PaginationError) async throws {
        switch error {
        case .fetchNextPage:
            try await fetchNextPage()
        case .refresh:
            try await refresh()
        }
    }
    
    private func fetchNextPageIfIdle() async {
        // Don't prefetch unless there's unloaded pages
        guard state != .completed else { return }
        
        // Don't prefetch if there's an error (avoid endless loop of errors).
        guard error == nil else { return }
        
        // Idle?
        guard loadingTask == nil else { return }
        
        try? await fetchNextPage()
    }
    
    private func pageDidLoad(_ page: Page<Element, AnyHashable>) {
        error = nil
        _elements.append(page: page.elements, with: mergeStrategy)
        
        if page.nextPageIdentifier != nil {
            state = .notCompleted
            if prefetchStrategy._needsPrefetchAfterPageLoaded(elementCount: elements.count) {
                Task {
                    await fetchNextPageIfIdle()
                }
            }
        } else {
            state = .completed
        }
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
protocol PageLoaderProtocol<Element> {
    associatedtype Element
    func refresh() async throws -> Page<Element, AnyHashable>
    func fetchNextPage() async throws -> Page<Element, AnyHashable>
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public enum PaginationState {
    /// No more page to load.
    case completed
    
    /// A page is missing.
    case notCompleted
    
    /// Next page is loading.
    case loadingNextPage
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public enum PaginationError: Error {
    case fetchNextPage(Error)
    case refresh(Error)
    
    public var underlyingError: Error {
        switch self {
        case let .fetchNextPage(error), let .refresh(error):
            return error
        }
    }
    
    public var localizedDescription: String {
        underlyingError.localizedDescription
    }
}
