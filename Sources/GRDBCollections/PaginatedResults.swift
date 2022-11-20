import Combine
import os.log

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
@MainActor
public class PaginatedResults<Element: Identifiable>: ObservableObject {
    @Published private var _elements: PaginatedCollection<Element>!
    @Published public private(set) var state = PaginationState.notCompleted
    @Published public private(set) var error: PaginationError?
    
    public var elements: PaginatedCollection<Element> { _elements }
    public let mergeStrategy: PaginationMergeStrategy<Element>
    
    let prefetchStrategy: any PaginationPrefetchStrategy
    var loader: (any PageLoaderProtocol)!
    
    public init(
        initialElements: [Element] = [],
        dataSource: some PaginationDataSource<Element>,
        prefetchStrategy: some PaginationPrefetchStrategy,
        mergeStrategy: PaginationMergeStrategy<Element> = .updateOrAppend)
    {
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
        
        self._elements = PaginatedCollection(makePrefetch: { [prefetchStrategy] index, elementCount in
            guard prefetchStrategy.needsPrefetchOnElementAppear(atIndex: index, elementCount: elementCount) else {
                return nil
            }
            return {
                Task { [weak self] in
                    self?.setNeedsPrefetch()
                }
            }
        })
        
        _elements.append(page: initialElements, with: mergeStrategy)
        
        if prefetchStrategy.needsInitialPrefetch() {
            setNeedsPrefetch()
        }
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
            if prefetchStrategy.needsPrefetchAfterPageLoaded(elementCount: elements.count) {
                setNeedsPrefetch()
            }
        } else {
            state = .completed
        }
    }
    
    private func setNeedsPrefetch() {
        // Don't prefetch unless there's unloaded pages
        guard state != .completed else { return }
        
        // Don't prefetch if there's an error (avoid endless loop of errors).
        guard error == nil else { return }
        
        Task {
            await loader.fetchNextPageIfIdle()
        }
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
protocol PageLoaderProtocol {
    func fetchNextPage() async throws
    func refresh() async throws
    func fetchNextPageIfIdle() async
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
