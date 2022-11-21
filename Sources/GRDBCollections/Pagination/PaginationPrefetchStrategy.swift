/// A type that controls how `PaginatedResults` prefetches pages.
///
/// ## Topics
///
/// ### Built-in Strategies
///
/// - ``firstPage``
/// - ``infiniteScroll(offscreenElementCount:)``
/// - ``minimumElementCount(_:)``
/// - ``noPrefetch``
///
/// ### Supporting Types
///
/// - ``BottomPaginationPrefetchStrategy``
/// - ``TopPaginationPrefetchStrategy``
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
    /// The strategy that prefetches pages until at least `count` elements
    /// are loaded.
    public static func minimumElementCount(_ count: Int) -> Self { .init(count: count) }
    
    /// The strategy that disables page prefetching.
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
    /// The strategy for infinite scrolling that always prefetches at least more
    /// `count` elements (until the list is exhausted).
    public static func infiniteScroll(offscreenElementCount count: Int) -> Self { .init(count: count) }
    
    /// The strategy that only prefetches the first page.
    public static var firstPage: Self { .init(count: 0) }
}
