@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public protocol PaginationPrefetchStrategy {
    func _needsInitialPrefetch() -> Bool
    func _needsPrefetchAfterPageLoaded(elementCount: Int) -> Bool
    func _needsPrefetchOnElementAppear(atIndex index: Int, elementCount: Int) -> Bool
}

// MARK: - TopPaginationPrefetchStrategy

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct TopPaginationPrefetchStrategy: PaginationPrefetchStrategy {
    let count: Int
    
    public init(count: Int) {
        self.count = count
    }
    
    public func _needsInitialPrefetch() -> Bool {
        count > 0
    }
    
    public func _needsPrefetchAfterPageLoaded(elementCount: Int) -> Bool {
        elementCount < count
    }
    
    public func _needsPrefetchOnElementAppear(atIndex index: Int, elementCount: Int) -> Bool {
        false
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginationPrefetchStrategy where Self == TopPaginationPrefetchStrategy {
    /// - parameter count: the minimum number of elements
    public static func minimumElements(_ count: Int) -> Self { .init(count: count) }
    
    public static var noPrefetch: Self { .init(count: 0) }
}

// MARK: - BottomPaginationPrefetchStrategy

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct BottomPaginationPrefetchStrategy: PaginationPrefetchStrategy {
    let count: Int
    
    public init(count: Int) {
        self.count = count
    }
    
    public func _needsInitialPrefetch() -> Bool {
        true
    }
    
    public func _needsPrefetchAfterPageLoaded(elementCount: Int) -> Bool {
        false
    }
    
    public func _needsPrefetchOnElementAppear(atIndex index: Int, elementCount: Int) -> Bool {
        (elementCount - index) <= count
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PaginationPrefetchStrategy where Self == BottomPaginationPrefetchStrategy {
    /// - parameter count: the number of elements below the last
    ///   visible element.
    public static func infiniteScroll(minimumElementsAtBottom count: Int) -> Self { .init(count: count) }
    
    public static var firstPage: Self { .init(count: 0) }
}
