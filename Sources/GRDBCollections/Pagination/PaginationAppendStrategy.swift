import Collections

/// The strategy for appending a new page to the previously fetched elements.
///
/// Elements in a ``PaginatedResults`` have an identifier.
/// A `PaginationAppendStrategy` specifies how elements in a new page are
/// appended to the previously fetched elements, in case of identifier reuse.
///
/// ## Topics
///
/// ### Enumeration cases
///
/// - ``ignoreOrAppend``
/// - ``removeAndAppend``
/// - ``updateOrAppend``
/// - ``custom(_:)``
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public enum PaginationAppendStrategy<Element, ID: Hashable> {
    /// Elements that were already fetched are removed, and the new page
    /// is appended.
    ///
    /// For example, if we start from:
    ///
    /// ```
    /// - id 1: Red
    /// - id 2: Green
    /// - id 3: Blue
    /// ```
    ///
    /// And the new page is:
    ///
    /// ```
    /// - id 1: Orange
    /// - id 4: Yellow
    /// ```
    ///
    /// The resulting elements are:
    ///
    /// ```
    /// - id 2: Green
    /// - id 3: Blue
    /// - id 1: Orange (appended)
    /// - id 4: Yellow (appended)
    /// ```
    case removeAndAppend
    
    /// Elements that were already fetched are updated in place, and only new
    /// elements are appended.
    ///
    /// For example, if we start from:
    ///
    /// ```
    /// - id 1: Red
    /// - id 2: Green
    /// - id 3: Blue
    /// ```
    ///
    /// And the new page is:
    ///
    /// ```
    /// - id 1: Orange
    /// - id 4: Yellow
    /// ```
    ///
    /// The resulting elements are:
    ///
    /// ```
    /// - id 1: Orange (updated)
    /// - id 2: Green
    /// - id 3: Blue
    /// - id 4: Yellow (appended)
    /// ```
    case updateOrAppend
    
    /// Elements that were already fetched are left unmodified, and new
    /// elements are appended.
    ///
    /// For example, if we start from:
    ///
    /// ```
    /// - id 1: Red
    /// - id 2: Green
    /// - id 3: Blue
    /// ```
    ///
    /// And the new page is:
    ///
    /// ```
    /// - id 1: Orange
    /// - id 4: Yellow
    /// ```
    ///
    /// The resulting elements are:
    ///
    /// ```
    /// - id 1: Red (unmodified)
    /// - id 2: Green
    /// - id 3: Blue
    /// - id 4: Yellow (appended)
    /// ```
    case ignoreOrAppend
    
    /// A custom appending strategy.
    ///
    /// - parameter newElements: The new Elements.
    /// - parameter dictionary: The ordered dictionary of previously fetched
    ///   elements.
    case custom((_ newElements: [Element], _ dictionary: inout OrderedDictionary<ID, Element>) -> Void)
}
