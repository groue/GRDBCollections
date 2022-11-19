import Combine
import os.log

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public class PaginatedResults<Element>: ObservableObject {
    public struct PaginatedElements: RandomAccessCollection {
        unowned var results: PaginatedResults?
        fileprivate var elements: [Element]
        public var count: Int { elements.count }
        public var startIndex: Int { elements.startIndex }
        public var endIndex: Int { elements.endIndex }
        public func index(after i: Int) -> Int { i + 1 }
        public subscript(position: Int) -> PaginatedElement<Element> {
            if let results,
               elements.distance(from: position, to: endIndex) <= results.threshold
            {
                return PaginatedElement(
                    element: elements[position],
                    prefetch: results.prefetchIfPossible)
            } else {
                return PaginatedElement(
                    element: elements[position],
                    prefetch: nil)
            }
        }
        
        init() {
            self.results = nil
            self.elements = []
        }
        
        init(results: PaginatedResults, elements: [Element] = []) {
            self.results = results
            self.elements = elements
        }
    }
    
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
    
    @Published public private(set) var elements = PaginatedElements()
    @Published public private(set) var state = PaginationState.notCompleted
    @Published public private(set) var error: PaginationError?
    @Published public private(set) var prefetch: PrefetchAction?
    
    let threshold: Int
    private var nextPage: AnyHashable?
    private var perform: ((PaginationAction) async throws -> Void)!
    private var isBusy: (() async -> Bool)!
    
    /// - parameter threshold: the number of bottom elements that trigger the
    ///   next page to be fetched when they appear on screen. If zero, next page
    ///   is never automatically fetched.
    public init(dataSource: some PaginatedDataSource<Element>, threshold: Int) {
        self.threshold = threshold
        
        let coordinator = PaginatedResultsCoordinator(
            dataSource: dataSource,
            willPerform: { @MainActor [weak self] action in
                guard let self else { return }
                self.error = nil
                switch action {
                case .refresh:
                    break
                case .fetchNextPage:
                    self.state = .loading
                }
            },
            didPerform: { @MainActor [weak self] action, elements, nextPage in
                guard let self else { return }
                
                switch action {
                case .refresh:
                    self.elements.elements = elements
                    #warning("TODO: merge")
                    // self.elements = OrderedDictionary(elements.lazy.map { ($0.id, $0) }, uniquingKeysWith: { (first, _) in first })
                case .fetchNextPage:
                    self.elements.elements.append(contentsOf: elements)
                    #warning("TODO: merge")
                    // self.elements.merge(elements.lazy.map { ($0.id, $0) }, uniquingKeysWith: { (_, new) in new })
                }
                
                self.nextPage = nextPage
                if nextPage != nil {
                    self.state = .notCompleted
                } else {
                    self.state = .completed
                }
            })
        
        self.perform = coordinator.perform
        self.isBusy = coordinator.isBusy
        self.elements = PaginatedElements(results: self)
        
        // Initial fetch
        if threshold > 0 {
            self.prefetch = PrefetchAction(results: self)
        }
    }
    
    @MainActor
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
    
    @MainActor
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
    
    func prefetchIfPossible() {
        // Don't prefetch if there's an error (avoid endless loop of errors).
        guard error == nil else { return }
        
        // Avoid runtime warning:
        // Publishing changes from within view updates is not allowed, this will cause undefined behavior.
        Task { @MainActor in
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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct PaginatedElement<Element> {
    public let element: Element
    let prefetch: (() -> Void)?
    
    public func prefetchIfNeeded() {
        prefetch?()
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension PaginatedElement: Identifiable where Element: Identifiable {
    public var id: Element.ID { element.id }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public enum PaginationState {
    /// No more page to load
    case completed
    
    /// A page is missing, but it is not loading.
    case notCompleted
    
    /// A page is loading
    case loading
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct Page<Element, PageIdentifier> {
    var elements: [Element]
    var nextPageIdentifier: PageIdentifier?
    
    public init(elements: [Element], nextPageIdentifier: PageIdentifier? = nil) {
        self.elements = elements
        self.nextPageIdentifier = nextPageIdentifier
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
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
    private let didPerform: (_ action: PaginationAction, _ elements: [Element], _ nextPage: AnyHashable?) async -> Void
    
    private var nextPageIdentifier: PageIdentifier?
    private var pageStates: [PageIdentifier: PageState] = [:]
    
    init(
        dataSource: DataSource,
        willPerform: @escaping (_ action: PaginationAction) async -> Void,
        didPerform: @escaping (_ action: PaginationAction, _ elements: [Element], _ nextPage: AnyHashable?) async -> Void)
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
            print("Don't fetch \(pageIdentifier)")
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
