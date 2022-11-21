/// A type that can fetch pages of elements one after the other.
///
/// ## Topics
///
/// ### Paginating Elements
///
/// - ``firstPageIdentifier-9uioa``
/// - ``page(at:)``
///
/// ### Associated Types
///
/// - ``Element``
/// - ``PageID``
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public protocol PageSource<Element> {
    /// The type of elements in a page.
    associatedtype Element
    
    /// The identifier for a page.
    associatedtype PageID: Hashable
    
    /// The identifier of the first page.
    ///
    /// If nil, there is no page.
    var firstPageIdentifier: PageID? { get }
    
    /// Returns the page for a given identifier.
    func page(at pageIdentifier: PageID) async throws -> (elements: [Element], nextPageIdentifier: PageID?)
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension PageSource where PageID == Never {
    /// The first page identifier is nil when `PageID` is `Never`.
    public var firstPageIdentifier: PageID? { nil }
}
