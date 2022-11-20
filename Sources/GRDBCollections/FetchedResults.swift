import Foundation // NSCache
import GRDB
import os.log

@MainActor
public final class FetchedResults<Element>: NSObject {
    /// A page of elements
    private class Page {
        let elements: [Element]
        
        init(elements: [Element]) {
            self.elements = elements
        }
    }
    
    /// The fetch state of a page
    private enum FetchState {
        /// Page fetch is being scheduled in an Operation
        case scheduled(Operation)
        
        /// Page has been fetched
        case fetched(Page)
    }
    
    private typealias PageIndex = Int
    
    fileprivate typealias Request = QueryInterfaceRequest<Element>
    fileprivate typealias FetchElements = (_ db: Database, _ request: Request, _ minimumCapacity: Int) throws -> [Element]
    
    /// The number of elements in the collection.
    public let count: Int
    
    /// The fetched request.
    private let request: Request
    
    /// The snapshot that provides database access.
    private let snapshot: any DatabaseSnapshotReader
    
    /// The fetch function (depends on the type of elements).
    private let fetchElements: FetchElements
    
    /// The maximum number of elements in a page.
    private let pageSize: Int
    
    /// The number of pages.
    private let pageCount: PageIndex
    
    /// The number of adjacent prefetched pages
    private let adjacentPageCount: Int
    
    /// A page cache.
    private let pageCache = NSCache<NSNumber, Page>()
    
    /// The loading state of pages.
    private var fetchedPages: [PageIndex: FetchState] = [:]
    
    /// The operation queue that schedules page fetch operations.
    private let prefetchQueue = OperationQueue()
    
    /// True until we have started prefetching
    private var needsInitialPrefetch = true
    
    /// Creates a ``FetchedResults``.
    ///
    /// - parameters:
    ///     - request: The fetched request.
    ///     - reader: The database access.
    ///     - configuration: The configuration.
    ///     - fetchElements: The function that fetches elements.
    fileprivate nonisolated init(
        snapshot: some DatabaseSnapshotReader,
        request: Request,
        configuration: FetchedResultsConfiguration,
        fetchElements: @escaping FetchElements)
    throws
    {
        self.snapshot = snapshot
        self.count = try snapshot.read(request.fetchCount)
        self.request = request
        self.fetchElements = fetchElements
        self.pageCache.countLimit = configuration.cachedPageCountLimit
        self.adjacentPageCount = configuration.adjacentPageCount
        self.pageSize = configuration.pageSize
        self.pageCount = 1 + (count - 1) / pageSize
        
        // We'll prefetch pages with cancellable Foundation operations.
        //
        // Prefetches are interrupted and cancelled from `cancelPrefetches()`,
        // when the FetchedResults needs database values that were not
        // prefetched yet: fetching the missing values has the highest priority.
        self.prefetchQueue.maxConcurrentOperationCount = snapshot.configuration.maximumReaderCount
        
        // Copy quality of service of database connection
        switch snapshot.configuration.readQoS.qosClass {
        case .background:
            self.prefetchQueue.qualityOfService = .background
        case .utility:
            self.prefetchQueue.qualityOfService = .utility
        case .default:
            self.prefetchQueue.qualityOfService = .default
        case .userInitiated:
            self.prefetchQueue.qualityOfService = .userInitiated
        case .userInteractive:
            self.prefetchQueue.qualityOfService = .userInteractive
        case .unspecified:
            break
        @unknown default:
            break
        }
    }
    
    private func page(at pageIndex: PageIndex) -> Page? {
        if let page = pageCache.object(forKey: NSNumber(value: pageIndex)) {
            return page
        }
        if case let .fetched(page) = fetchedPages[pageIndex] {
            return page
        }
        return nil
    }
    
    private func setPage(_ page: Page, at pageIndex: PageIndex) {
        fetchedPages[pageIndex] = .fetched(page)
        pageCache.setObject(page, forKey: NSNumber(value: pageIndex))
    }
    
    @inline(__always)
    nonisolated private func pageIndex(forElementAt index: Index) -> PageIndex {
        index / pageSize
    }
    
    nonisolated private func requestForPage(at pageIndex: PageIndex) -> Request {
        request.limit(pageSize, offset: pageIndex * pageSize)
    }
    
    nonisolated private func fetchPage(_ db: Database, at pageIndex: PageIndex) throws -> Page {
        // os_log("Fetch %ld", log: debugLog, type: .debug, pageIndex)
        let pageRequest = requestForPage(at: pageIndex)
        let elements = try fetchElements(db, pageRequest, /* minimumCapacity: */ pageSize)
        return Page(elements: elements)
    }
}

// MARK: - Prefetching

extension FetchedResults {
    private func prefetchElements(around index: Index) {
        needsInitialPrefetch = false
        
        let pageIndexes = prefetchedPageIndexes(around: index)
        
        for pageIndex in fetchedPages.keys
        where pageIndexes.contains(pageIndex) == false
        {
            fetchedPages.removeValue(forKey: pageIndex)
        }
        
        prefetchPages(at: pageIndexes)
    }
    
    /// Returns the page indexes to prefetch around an element index, in the
    /// preferred order of prefetch.
    nonisolated private func prefetchedPageIndexes(around index: Index) -> [PageIndex] {
        let pageIndex = pageIndex(forElementAt: index)
        
        // Pages to prefetch, in the order of prefetch:
        var pageIndexes: [PageIndex] = []
        pageIndexes.reserveCapacity(adjacentPageCount)
        
        // Page and next pages
        var next = pageIndex
        while pageIndexes.count <= adjacentPageCount / 2, next < pageCount {
            pageIndexes.append(next)
            next += 1
        }
        
        // Previous pages
        var previous = pageIndex - 1
        while pageIndexes.count < adjacentPageCount, previous >= 0 {
            pageIndexes.append(previous)
            previous -= 1
        }
        
        // Next pages if there's not enough previous pages
        while pageIndexes.count < adjacentPageCount, next < pageCount {
            pageIndexes.append(next)
            next += 1
        }
        
        assert(pageIndexes.count == Swift.min(pageCount, adjacentPageCount))
        return pageIndexes
    }
    
    /// - parameter pageIndexes: the page indexes to prefetch, in the
    /// preferred order of prefetch.
    private func prefetchPages<PageIndexes>(at pageIndexes: PageIndexes)
    where PageIndexes: Collection, PageIndexes.Element == PageIndex
    {
        var previousOperation: Operation?
        for pageIndex in pageIndexes {
            if fetchedPages[pageIndex] != nil {
                // Page already fetched or scheduled in an operation
                continue
            }
            
            if let page = pageCache.object(forKey: NSNumber(value: pageIndex)) {
                // Page cached
                fetchedPages[pageIndex] = .fetched(page)
                continue
            }
            
            // os_log("Prefetch %ld", log: debugLog, type: .debug, pageIndex)
            let operation = makePagePrefetchOperation(at: pageIndex)
            fetchedPages[pageIndex] = .scheduled(operation)
            
            // TODO: manage page priority when maxConcurrentOperationCount > 1
            if let previousOperation,
               prefetchQueue.maxConcurrentOperationCount == 1
            {
                operation.addDependency(previousOperation)
            }
            prefetchQueue.addOperation(operation)
            
            previousOperation = operation
        }
    }
    
    nonisolated private func makePagePrefetchOperation(at pageIndex: PageIndex) -> Operation {
        BlockOperation { [self] in
            do {
                try withIntervalSignpost(name: "Fetch", id: .id(pageIndex)) {
                    let page = try snapshot.read { db in
                        try fetchPage(db, at: pageIndex)
                    }
                    
                    DispatchQueue.main.async { [self] in
                        // os_log("Did prefetch %ld", log: debugLog, type: .debug, pageIndex)
                        setPage(page, at: pageIndex)
                    }
                }
            } catch {
                // Likely interrupted from cancelPrefetches()
                // os_log("Failed prefetch %ld", log: debugLog, type: .debug, pageIndex)
                emitSignpostEvent("Interrupted")
            }
        }
    }
    
    private func cancelPrefetches() {
        prefetchQueue.cancelAllOperations()
        for (pageIndex, pageState) in fetchedPages {
            if case .scheduled = pageState {
                fetchedPages[pageIndex] = nil
            }
        }
        snapshot.interrupt()
    }
}

// MARK: - RandomAccessCollection

extension FetchedResults: RandomAccessCollection {
    public typealias Index = Int
    public var startIndex: Index { 0 }
    public var endIndex: Index { count }
    
    public subscript(index: Index) -> Element {
        let (pageIndex, elementIndex) = index.quotientAndRemainder(dividingBy: pageSize)
        if let page = page(at: pageIndex) {
            if needsInitialPrefetch || elementIndex == 0 {
                prefetchElements(around: index)
            }
            return page.elements[elementIndex]
        }
        
        // os_log("Block at %ld", log: debugLog, type: .debug, pageIndex)
        let page = withIntervalSignpost(name: "Block", id: .exclusive) {
            cancelPrefetches()
            let page = try! snapshot.read { db in
                try fetchPage(db, at: pageIndex)
            }
            setPage(page, at: pageIndex)
            prefetchElements(around: index)
            return page
        }
        
        return page.elements[index - pageIndex * pageSize]
    }
}

// MARK: - FetchedResultsConfiguration

public struct FetchedResultsConfiguration {
    var cachedPageCountLimit: Int
    var pageSize: Int
    var adjacentPageCount: Int
    
    public static var `default`: Self {
        FetchedResultsConfiguration(
            cachedPageCountLimit: 0,
            pageSize: 50,
            adjacentPageCount: 20)
    }
    
    public init(
        cachedPageCountLimit: Int,
        pageSize: Int,
        adjacentPageCount: Int)
    {
        precondition(pageSize > 0, "pageSize must be greater than zero")
        precondition(adjacentPageCount > 0, "adjacentPageCount must be greater than zero")
        
        self.cachedPageCountLimit = cachedPageCountLimit
        self.pageSize = pageSize
        self.adjacentPageCount = adjacentPageCount
    }
}

// MARK: - FetchedResults + DatabaseValueConvertible

extension QueryInterfaceRequest where RowDecoder: DatabaseValueConvertible {
    public func fetchResults(
        in snapshot: some DatabaseSnapshotReader,
        configuration: FetchedResultsConfiguration = .default)
    throws -> FetchedResults<RowDecoder>
    {
        try FetchedResults(
            snapshot: snapshot,
            request: self,
            configuration: configuration,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}

// MARK: - FetchedResults + DatabaseValueConvertible & StatementColumnConvertible

extension QueryInterfaceRequest where RowDecoder: DatabaseValueConvertible & StatementColumnConvertible {
    public func fetchResults(
        in snapshot: some DatabaseSnapshotReader,
        configuration: FetchedResultsConfiguration = .default)
    throws -> FetchedResults<RowDecoder>
    {
        try FetchedResults(
            snapshot: snapshot,
            request: self,
            configuration: configuration,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}

// MARK: - FetchedResults + Record

extension QueryInterfaceRequest where RowDecoder: FetchableRecord {
    public func fetchResults(
        in snapshot: some DatabaseSnapshotReader,
        configuration: FetchedResultsConfiguration = .default)
    throws -> FetchedResults<RowDecoder>
    {
        try FetchedResults(
            snapshot: snapshot,
            request: self,
            configuration: configuration,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}

// MARK: - FetchedResults + Row

extension QueryInterfaceRequest where RowDecoder == Row {
    public func fetchResults(
        in snapshot: some DatabaseSnapshotReader,
        configuration: FetchedResultsConfiguration = .default)
    throws -> FetchedResults<RowDecoder>
    {
        try FetchedResults(
            snapshot: snapshot,
            request: self,
            configuration: configuration,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}

// MARK: - Logging

enum MeasureID {
    case exclusive
    case id(Int)
}

private let debugLog = OSLog(subsystem:"com.github.groue.GRDBCollections", category: "debug")

// Set to true when profiling with Instruments
#if true
@available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
let signposter = OSSignposter(logHandle: OSLog(subsystem:"com.github.groue.GRDBCollections", category:.pointsOfInterest))

func withIntervalSignpost<T>(name: StaticString, id: MeasureID, execute: () throws -> T) rethrows -> T {
    guard #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) else {
        return try execute()
    }
    
    // signposter.withIntervalSignpost does not handle errors correctly :-/
    let state: OSSignpostIntervalState
    switch id {
    case .exclusive:
        state = signposter.beginInterval(name, id: .exclusive)
    case let .id(id):
        state = signposter.beginInterval(name, id: .init(UInt64(id)))
    }
    
    defer {
        signposter.endInterval(name, state)
    }
    
    return try execute()
}

func emitSignpostEvent(_ name: StaticString) {
    guard #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) else {
        return
    }
    
    signposter.emitEvent("Interrupted")
}

#else
@inline(__always)
func withIntervalSignpost<T>(
    name: @autoclosure() -> StaticString,
    id: @autoclosure() -> MeasureID,
    execute: () throws -> T)
rethrows -> T
{
    try execute
}

@inline(__always)
func emitSignpostEvent(name: @autoclosure() -> StaticString) { }
#endif
