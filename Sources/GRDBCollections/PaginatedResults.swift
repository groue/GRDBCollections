import Combine
import os.log

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
@MainActor
public class PaginatedResults<Element: Identifiable>: ObservableObject {
    public struct PrefetchAction: Equatable {
        var id: Int = 0
        var results: PaginatedResults
        
        public func callAsFunction() async {
            try? await results.fetchNextPage()
        }
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    @Published private var _elements: PaginatedCollection<Element>!
    @Published public private(set) var state = PaginationState.notCompleted
    @Published public private(set) var error: PaginationError?
    @Published public private(set) var prefetch: PrefetchAction?
    
    public var elements: PaginatedCollection<Element> { _elements }
    public let mergeStrategy: PaginationMergeStrategy<Element>
    
    let prefetchStrategy: any PaginationPrefetchStrategy
    private var nextPage: AnyHashable?
    private var perform: ((PaginationAction) async throws -> Void)!
    private var isBusy: (() async -> Bool)!
    
    public init(
        initialElements: [Element] = [],
        dataSource: some PaginatedDataSource<Element>,
        prefetchStrategy: some PaginationPrefetchStrategy,
        mergeStrategy: PaginationMergeStrategy<Element> = .deleteAndAppend)
    {
        self.prefetchStrategy = prefetchStrategy
        self.mergeStrategy = mergeStrategy
        
        let coordinator = PaginatedResultsCoordinator(
            dataSource: dataSource,
            willPerform: { [weak self] action in
                self?.willPerform(action)
            },
            didPerform: { [weak self] action, newElements, nextPage in
                self?.didPerform(action, newElements: newElements, nextPage: nextPage)
            })
        self.perform = coordinator.perform
        self.isBusy = coordinator.isBusy
        
        self._elements = PaginatedCollection(makePrefetch: { [prefetchStrategy] index, elementCount in
            guard prefetchStrategy.needsPrefetchOnElementAppear(atIndex: index, elementCount: elementCount) else {
                return nil
            }
            return {
                Task { [weak self] in
                    self?.prefetchIfPossible()
                }
            }
        })
        _elements.append(page: initialElements, with: mergeStrategy)
        
        // Initial fetch
        if prefetchStrategy.needsInitialPrefetch() {
            prefetch = PrefetchAction(results: self)
        }
    }
    
    public func fetchNextPage() async throws {
        let previousState = self.state
        do {
            try await perform(.fetchNextPage)
        } catch {
            self.error = .nextPage(error)
            self.state = previousState
            throw error
        }
    }
    
    public func refresh() async throws {
        let previousState = self.state
        do {
            try await perform(.refresh)
        } catch {
            self.error = .refresh(error)
            self.state = previousState
            throw error
        }
    }
    
    private func willPerform(_ action: PaginationAction) {
        self.error = nil
        
        switch action {
        case .refresh:
            break
        case .fetchNextPage:
            self.state = .loading
        }
    }
    
    private func didPerform(_ action: PaginationAction, newElements: [Element], nextPage: AnyHashable?) {
        if action == .refresh {
            _elements.removeAll()
        }
        
        _elements.append(page: newElements, with: mergeStrategy)
        self.nextPage = nextPage
        if nextPage != nil {
            state = .notCompleted
            if prefetchStrategy.needsPrefetchAfterPageLoaded(elementCount: elements.count) {
                prefetchIfPossible()
            }
        } else {
            state = .completed
        }
    }
    
    func prefetchIfPossible() {
        // Don't prefetch if there's an error (avoid endless loop of errors).
        guard error == nil else { return }
        guard state != .completed else { return }
        
        // Avoid runtime warning:
        // Publishing changes from within view updates is not allowed, this will cause undefined behavior.
        Task {
            if await isBusy() {
                return
            }
            if let prefetch = prefetch {
                self.prefetch = PrefetchAction(id: prefetch.id + 1, results: self)
            } else {
                self.prefetch = PrefetchAction(results: self)
            }
        }
    }
}

// MARK: - PaginatedElement

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedElement<Element> {
    public let element: Element
    let prefetch: (() -> Void)?
    
    public func prefetchIfNeeded() {
        prefetch?()
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedElement: Identifiable where Element: Identifiable {
    public var id: Element.ID { element.id }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public enum PaginationState {
    /// No more page to load.
    case completed
    
    /// A page is missing.
    case notCompleted
    
    /// A page is loading.
    case loading
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

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct Page<Element, PageIdentifier> {
    var elements: [Element]
    var nextPageIdentifier: PageIdentifier?
    
    public init(elements: [Element], nextPageIdentifier: PageIdentifier? = nil) {
        self.elements = elements
        self.nextPageIdentifier = nextPageIdentifier
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public protocol PaginatedDataSource<Element> {
    associatedtype Element
    associatedtype PageIdentifier: Hashable
    
    var firstPageIdentifier: PageIdentifier { get }
    func page(at pageIdentifier: PageIdentifier) async throws -> Page<Element, PageIdentifier>
}

private enum PaginationAction {
    case refresh
    case fetchNextPage
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
private actor PaginatedResultsCoordinator<DataSource: PaginatedDataSource> {
    typealias Element = DataSource.Element
    typealias PageIdentifier = DataSource.PageIdentifier
    
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
    
    private var nextPageIdentifier: PageIdentifier?
    private var pageStates: [PageIdentifier: PageState] = [:]
    
    init(
        dataSource: DataSource,
        willPerform: @escaping (_ action: PaginationAction) async -> Void,
        didPerform: @escaping (_ action: PaginationAction, _ newElements: [Element], _ nextPage: AnyHashable?) async -> Void)
    {
        self.dataSource = dataSource
        self.willPerform = willPerform
        self.didPerform = didPerform
    }
    
    func perform(action: PaginationAction) async throws {
        if action == .refresh {
            for pageState in self.pageStates.values {
                pageState.cancel()
            }
            self.pageStates = [:]
        }
        
        let pageIdentifier: PageIdentifier
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
        
        print("Fetch \(pageIdentifier)")
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
                print("cancelled")
            } catch {
                pageStates.removeValue(forKey: pageIdentifier)
                throw error
            }
        }
        pageStates[pageIdentifier] = .loading(task)
        return try await task.value
    }
    
    func isBusy() async -> Bool {
        pageStates.values.contains {
            if case .loading = $0 { return true }
            return false
        }
    }
}
