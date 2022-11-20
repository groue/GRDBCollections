import Combine
import os.log

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
@MainActor
public class PaginatedResults<Element, ID: Hashable>: ObservableObject {
    @Published private var _elements: PaginatedCollection<Element, ID>!
    @Published public private(set) var state = PaginationState.notCompleted
    @Published public private(set) var error: PaginationError?
    
    public var elements: PaginatedCollection<Element, ID> { _elements }
    public let mergeStrategy: PaginationMergeStrategy<Element, ID>
    
    let idKeyPath: KeyPath<Element, ID>
    let prefetchStrategy: any PaginationPrefetchStrategy
    var loader: (any PageLoaderProtocol)!
    
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
        
        self.loader = PageLoader(
            dataSource: dataSource,
            willPerform: { [weak self] action in
                self?.willPerform(action)
            },
            didPerform: { [weak self] action, newElements, nextPage in
                self?.didPerform(action, newElements: newElements, nextPage: nextPage)
            })
        
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
        let previousState = state
        do {
            try await loader.fetchNextPage()
        } catch {
            self.error = .nextPage(error)
            self.state = previousState
            throw error
        }
    }
    
    public func refresh() async throws {
        let previousState = state
        do {
            try await loader.refresh()
        } catch {
            self.error = .refresh(error)
            self.state = previousState
            throw error
        }
    }
    
    public func removeAllAndRefresh() async throws {
        _elements.removeAll()
        error = nil
        state = .loadingNextPage
        try await loader.refresh()
    }
    
    private func fetchNextPageIfIdle() async {
        // Don't prefetch unless there's unloaded pages
        guard state != .completed else { return }
        
        // Don't prefetch if there's an error (avoid endless loop of errors).
        guard error == nil else { return }
        
        let previousState = state
        do {
            try await loader.fetchNextPageIfIdle()
        } catch {
            self.error = .nextPage(error)
            self.state = previousState
        }
    }
    
    private func willPerform(_ action: PaginationAction) {
        error = nil
        
        switch action {
        case .refresh:
            break
        case .fetchNextPage:
            state = .loadingNextPage
        }
    }
    
    private func didPerform(_ action: PaginationAction, newElements: [Element], nextPage: AnyHashable?) {
        if action == .refresh {
            _elements.removeAll()
        }
        
        _elements.append(page: newElements, with: mergeStrategy)
        
        if nextPage != nil {
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
protocol PageLoaderProtocol {
    func fetchNextPage() async throws
    func refresh() async throws
    func fetchNextPageIfIdle() async throws
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
    case refresh(Error)
    case nextPage(Error)
    
    public var underlyingError: Error {
        switch self {
        case let .refresh(error), let .nextPage(error):
            return error
        }
    }
    
    public var localizedDescription: String {
        underlyingError.localizedDescription
    }
}
