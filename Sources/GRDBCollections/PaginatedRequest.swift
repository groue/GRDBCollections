import GRDB

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedRequest<Element> {
    fileprivate typealias Request = QueryInterfaceRequest<Element>
    fileprivate typealias FetchElements = (_ db: Database, _ request: Request, _ minimumCapacity: Int) throws -> [Element]
    
    /// The total number of elements.
    public let count: Int
    
    /// The fetched request.
    private let request: Request?
    
    /// The snapshot that provides database access.
    private let snapshot: (any DatabaseSnapshotReader)?
    
    /// The fetch function (depends on the type of elements).
    private let fetchElements: FetchElements
    
    /// The maximum number of elements in a page.
    private let pageSize: Int
    
    public static var empty: Self { PaginatedRequest() }
    
    private init() {
        self.count = 0
        self.pageSize = 1
        self.request = nil
        self.snapshot = nil
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
        self.count = try snapshot.read(request.fetchCount)
        self.request = request
        self.fetchElements = fetchElements
        self.pageSize = pageSize
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginatedRequest: PaginationDataSource {
    public var firstPageIdentifier: Int { 0 }
    
    public func page(at pageIdentifier: Int) async throws -> Page<Element, Int> {
        guard let snapshot, let request else {
            return Page(elements: [], nextPageIdentifier: nil)
        }
        
        return try await snapshot.read { db in
            let pageRequest = request.limit(pageSize, offset: pageIdentifier)
            let elements = try fetchElements(db, pageRequest, /* minimumCapacity: */ pageSize)
            let nextOffset = pageIdentifier + pageSize
            return Page(
                elements: elements,
                nextPageIdentifier: nextOffset < count ? nextOffset : nil)
        }
    }
}

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

