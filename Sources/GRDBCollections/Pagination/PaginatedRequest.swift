import GRDB

#warning("TODO: how to synchronously display an initial page?")
/// A database request that fetches pages of elements, one page after the other.
///
/// You create a `PaginatedRequest` with the
/// `GRDB.QueryInterfaceRequest.paginated(in:pageSize:)` method,
/// that accepts a `GRDB.DatabaseSnapshotReader` argument:
///
/// ```swift
/// let snapshot: some DatabaseSnapshotReader
/// let request = Player.order(Column("score"))
/// let paginatedRequest = try request.paginated(in: snapshot, pageSize: 50)
/// ```
///
/// `PaginatedRequest` conforms to ``PageSource`` so that it can feed
/// a ``PaginatedResults`` and a SwiftUI `List`.
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedRequest<Element> {
    fileprivate typealias Request = QueryInterfaceRequest<Element>
    fileprivate typealias FetchElements = (_ db: Database, _ request: Request, _ minimumCapacity: Int) throws -> [Element]
    
    /// The snapshot that provides database access.
    private let snapshot: (any DatabaseSnapshotReader)?
    
    /// The fetched request.
    private let request: Request?
    
    /// The total number of elements.
    public let count: Int
    
    /// The maximum number of elements in a page.
    private let pageSize: Int
    
    /// The fetch function (depends on the type of elements).
    private let fetchElements: FetchElements
    
    /// The empty request.
    public static var empty: Self { PaginatedRequest() }
    
    private init() {
        self.snapshot = nil
        self.request = nil
        self.count = 0
        self.pageSize = 1
        self.fetchElements = { _, _, _ in [] }
    }
    
    fileprivate init(
        snapshot: some DatabaseSnapshotReader,
        request: Request,
        pageSize: Int,
        fetchElements: @escaping FetchElements)
    throws
    {
        precondition(pageSize > 0, "pageSize must be greater than zero")
        
        self.snapshot = snapshot
        self.request = request
        self.count = try snapshot.read(request.fetchCount)
        self.pageSize = pageSize
        self.fetchElements = fetchElements
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedRequest: PageSource {
    public func firstPageIdentifier() -> Int? { 0 }
    
    public func page(at pageIdentifier: Int) async throws -> (elements: [Element], nextPageIdentifier: Int?) {
        guard let snapshot, let request else {
            return (elements: [], nextPageIdentifier: nil)
        }
        
        return try await snapshot.read { db in
            let pageRequest = request.limit(pageSize, offset: pageIdentifier)
            let elements = try fetchElements(db, pageRequest, /* minimumCapacity: */ pageSize)
            let nextOffset = pageIdentifier + pageSize
            return (
                elements: elements,
                nextPageIdentifier: nextOffset < count ? nextOffset : nil)
        }
    }
}

// MARK: - PaginatedRequest + DatabaseValueConvertible

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension QueryInterfaceRequest where RowDecoder: DatabaseValueConvertible {
    public func paginated(
        in snapshot: some DatabaseSnapshotReader,
        pageSize: Int)
    throws -> PaginatedRequest<RowDecoder>
    {
        try PaginatedRequest(
            snapshot: snapshot,
            request: self,
            pageSize: pageSize,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}

// MARK: - PaginatedRequest + DatabaseValueConvertible & StatementColumnConvertible

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension QueryInterfaceRequest where RowDecoder: DatabaseValueConvertible & StatementColumnConvertible {
    public func paginated(
        in snapshot: some DatabaseSnapshotReader,
        pageSize: Int)
    throws -> PaginatedRequest<RowDecoder>
    {
        try PaginatedRequest(
            snapshot: snapshot,
            request: self,
            pageSize: pageSize,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}

// MARK: - PaginatedRequest + FetchableRecord

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension QueryInterfaceRequest where RowDecoder: FetchableRecord {
    public func paginated(
        in snapshot: some DatabaseSnapshotReader,
        pageSize: Int)
    throws -> PaginatedRequest<RowDecoder>
    {
        try PaginatedRequest(
            snapshot: snapshot,
            request: self,
            pageSize: pageSize,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}

// MARK: - PaginatedRequest + Row

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension QueryInterfaceRequest where RowDecoder == Row {
    public func paginated(
        in snapshot: some DatabaseSnapshotReader,
        pageSize: Int)
    throws -> PaginatedRequest<RowDecoder>
    {
        try PaginatedRequest(
            snapshot: snapshot,
            request: self,
            pageSize: pageSize,
            fetchElements: { db, request, minimumCapacity in
                try Array(request.fetchCursor(db), minimumCapacity: minimumCapacity)
            })
    }
}
