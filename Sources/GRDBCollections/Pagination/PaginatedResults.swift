import Combine
import os.log

/// An observable object that presents the elements of a pagination source
/// to SwiftUI.
///
/// ## Overview
///
/// A `PaginatedResults` fetches pages of elements, one page after the other.
/// It is well suited for displaying large collections in a SwiftUI `List`, or
/// for accessing the results of a paginated server api.
///
/// `PaginatedResults` can prefetch pages automatically, according to your
/// preferred prefetch strategy. This is how your application users can
/// experience, for example, a classical "infinite scroll".
///
/// `PaginatedResults` also supports pull-to-refresh, and error handling.
///
/// We'll see below how to paginate the results of a database request. See the
/// ``PageSource`` protocol if you want to define a custom page source that is
/// not the database.
///
/// ## Paginate Database Results
///
/// To paginate the results of a database request, you need a
/// `GRDB.QueryInterfaceRequest`, and a database connection that conforms to
/// `GRDB.DatabaseSnapshotReader`.
///
/// For example:
///
/// ```swift
/// let snapshot: some DatabaseSnapshotReader
/// let request = Player.order(Column("score"))
/// ```
///
/// From the request and the snapshot, build a `PaginatedRequest`, and then a
/// `PaginatedResults`:
///
/// ```swift
/// let paginatedRequest = try request.paginated(in: snapshot, pageSize: 50)
/// let results = PaginatedResults(paginatedPlayers)
/// ```
///
/// ## Example: Feeding a SwiftUI List with GRDBQuery
///
/// This section provides a sample code that uses
/// [GRDBQuery](https://github.com/groue/GRDBQuery) in order to feed a SwiftUI
/// `List` from the database.
///
/// ```swift
/// import Combine
/// import GRDB
/// import GRDBCollections
/// import GRDBQuery
/// import SwiftUI
///
/// // The view that displays a paginated list of players.
/// // It loads a `PaginatedRequest` from the environment
/// // and builds a `PaginatedResults`.
/// struct PlayersView: View {
///     @Query(PaginatedPlayersRequest(pageSize: 50), in: \.dbPool) var paginatedPlayers
///
///     var body: some View {
///         PlayerList(players: PaginatedResults(paginatedPlayers))
///     }
/// }
///
/// // A helper view that observes its `PaginatedResults`
/// // and displays the list of players.
/// struct PlayerList: View {
///     @ObservedObject var players: PaginatedResults<Player, Player.ID>
///
///     var body: some View {
///         List(players.elements) { element in
///             PlayerRow(player: element.value)
///                 .onAppear(element, prefetchIfNeeded: players)
///         }
///     }
/// }
///
/// // A row in the list of players
/// struct PlayerRow: View {
///     let player: Player
///
///     var body: some View {
///         Text(player.name)
///     }
/// }
///
/// // The `Queryable` type that builds a `PaginatedRequest`
/// // of players from the SwiftUI environment.
/// struct PaginatedPlayersRequest: Queryable {
///     static var defaultValue: PaginatedRequest<Player> { .empty }
///     var pageSize: Int
///
///     func publisher(in dbPool: DatabasePool) -> AnyPublisher<PaginatedRequest<Player>, Error> {
///         dbPool.readPublisher { db in
///             let snapshot = try DatabaseSnapshotPool(db)
///             let request = Player.order(Column("score"))
///             let paginatedRequest = try request.paginated(in: snapshot, pageSize: pageSize)
///             return paginatedRequest
///         }
///         .eraseToAnyPublisher()
///     }
/// }
/// ```
///
/// ### Prefetching Pages
///
/// By default, `PaginatedResults` fetches pages on demand, as the user scrolls
/// to the last row of the list.
///
/// You can further control how pages are prefetched with the `prefetchStrategy`
/// parameter of the `PaginatedResults` initializers.
///
/// For example, you can configure an infinite scroll that always prefetches
/// at least 50 more elements (until the list is exhausted):
///
/// ```swift
/// PaginatedResults(players, prefetchStrategy: .infiniteScroll(offscreenElementCount: 50))
/// ```
///
/// In the next example, at least 20 elements are prefetched, and that's it.
/// Next pages will only be fetched if you call the ``fetchNextPage()`` method:
///
/// ```swift
/// PaginatedResults(players, prefetchStrategy: .minimumElementCount(20))
/// ```
///
/// > Important: Infinite scroll only works if you call the
/// > `View.onAppear(_:prefetchIfNeeded:)` method on each row of the list,
/// > as below:
/// >
/// > ```swift
/// > struct PlayerList: View {
/// >     @ObservedObject var players: PaginatedResults<Player, Player.ID>
/// >
/// >     var body: some View {
/// >         List(players.elements) { element in
/// >             PlayerRow(player: element.value)
/// >                 .onAppear(element, prefetchIfNeeded: players)
/// >         }
/// >     }
/// > }
/// > ```
/// >
/// > You don't need to call `onAppear(_:prefetchIfNeeded:)` if you do not rely
/// > on the scrolling position in order to prefetch pages.
///
/// See ``PaginationPrefetchStrategy`` for more options.
///
/// ## Topics
///
/// ### Creating a PaginatedResults
///
/// - ``init(_:initialElementCount:prefetchDistance:appendStrategy:)``
/// - ``init(_:id:initialElementCount:prefetchDistance:appendStrategy:)``
///
/// ### Accessing the Paginated Elements
///
/// - ``elements``
/// - ``PaginatedCollection``
///
/// ### Accessing the Pagination State
///
/// - ``isFetchingPage``
/// - ``paginationError``
/// - ``paginationState``
/// - ``PaginationError``
/// - ``PaginationState``
///
/// ### Performing Pagination Actions
///
/// - ``fetchNextPage()``
/// - ``prefetch()``
/// - ``refresh()``
/// - ``removeAllAndRefresh()``
/// - ``retry(from:)``
///
/// ### Supporting Types
///
/// - ``PageSource``
/// - ``PaginationAppendStrategy``
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
@MainActor
public class PaginatedResults<Element, ID: Hashable>: ObservableObject {
    /// A boolean value indicating if some page is currently fetched.
    ///
    /// Use this published property in order to update the user interface
    /// whenever the `PaginatedResults` is fetching a page.
    public var isFetchingPage: Bool { fetchingTask != nil }

    /// The pagination state.
    ///
    /// Use this published property in order to update the user interface
    /// according to the pagination state.
    ///
    /// For example:
    ///
    /// ```swift
    /// List {
    ///     Section {
    ///         ForEach(players.elements) { element in
    ///             PlayerRow(player: element.value)
    ///                 .onAppear(element, prefetchIfNeeded: players)
    ///         }
    ///     } footer: {
    ///         switch players.paginationState {
    ///         case .fetchingNextPage:
    ///             Text("Loading…")
    ///         case .completed:
    ///             Text("End of List")
    ///         case .notCompleted:
    ///             Button {
    ///                 Task {
    ///                     try await players.fetchNextPage()
    ///                 }
    ///             } label: { Text("Load Next Page") }
    ///         }
    ///     }
    /// }
    /// ```
    @Published public private(set) var paginationState = PaginationState.notCompleted
    
    /// The eventual pagination error.
    ///
    /// This published property contains the eventual error that prevented the
    /// last page fetch to fail.
    @Published public private(set) var paginationError: PaginationError?
    
    /// The collection of paginated elements.
    @Published public private(set) var elements: PaginatedCollection<Element, ID>!
    
    /// The configuration.
    public let configuration: PaginatedResultsConfiguration
    
    @Published private var fetchingTask: Task<Page<Element>, any Error>?
    private let idKeyPath: KeyPath<Element, ID>
    private let appendStrategy: PaginationAppendStrategy<Element, ID>
    private var loader: any PageLoaderProtocol<Element>
    
    /// Creates an instance that paginates and identifies elements loaded from
    /// the underlying pagination source with the provided key path.
    ///
    /// - parameters:
    ///     - pageSource: The pagination source.
    ///     - id: The key path to elements’ identifier.
    ///     - initialElementCount: The minimal number of elements to
    ///       fetch initially.
    ///     - prefetchDistance: The distance to the bottom of the list that
    ///       triggers page prefetch.
    ///     - appendStrategy: A strategy for appending new pages. By default,
    ///       eventual existing elements are updated with the new ones, and new
    ///       elements are appended.
    public init(
        _ pageSource: some PageSource<Element>,
        id: KeyPath<Element, ID>,
        configuration: PaginatedResultsConfiguration,
        appendStrategy: PaginationAppendStrategy<Element, ID> = .updateOrAppend)
    {
        self.idKeyPath = id
        self.initialElementCount = initialElementCount
        self.prefetchDistance = prefetchDistance
        self.appendStrategy = appendStrategy
        self.loader = PageLoader(pageSource)
        self.elements = PaginatedCollection(id: id, prefetchDistance: prefetchDistance, appendStrategy: appendStrategy)
        
        if initialElementCount > 0  {
            Task {
                await prefetch()
            }
        }
    }
    
    /// Creates an instance that paginates elements loaded from the underlying
    /// pagination source.
    ///
    /// - parameters:
    ///     - pageSource: The pagination source.
    ///     - configuration: The configuration.
    ///     - appendStrategy: A strategy for appending new pages. By default,
    ///       eventual existing elements are updated with the new ones, and new
    ///       elements are appended.
    public convenience init(
        _ pageSource: some PageSource<Element>,
        configuration: PaginatedResultsConfiguration,
        appendStrategy: PaginationAppendStrategy<Element, Element.ID> = .updateOrAppend)
    where Element: Identifiable, ID == Element.ID
    {
        self.init(
            pageSource,
            id: \.id,
            initialElementCount: initialElementCount,
            prefetchDistance: prefetchDistance,
            appendStrategy: appendStrategy)
    }
    
    /// Fetches the next page.
    ///
    /// Any pending page request is cancelled when this method is called.
    ///
    /// - throws: An error if the page could not be fetched. In case of
    ///   cancellation, no error is thrown.
    public func fetchNextPage() async throws {
        fetchingTask?.cancel()
        
        let previousState = paginationState
        let task = Task {
            try await loader.fetchNextPage()
        }
        fetchingTask = task
        paginationState = .fetchingNextPage
        
        do {
            let page = try await task.value
            if fetchingTask == task {
                paginationError = nil
                fetchingTask = nil
                pageDidLoad(page)
            }
        } catch is CancellationError {
        } catch {
            if fetchingTask == task {
                fetchingTask = nil
                paginationState = previousState
                self.paginationError = .fetchNextPage(error)
                throw error
            }
        }
    }
    
    #warning("TODO: do we really prefetch as many offscreen elements as specified?")
    /// Prefetches the next page if idle.
    ///
    /// This method is automatically called for you, according to the prefetch
    /// strategy, if you use the `View.onAppear(_:prefetchIfNeeded:)` in you
    /// SwiftUI `List`, as below:
    ///
    /// ```swift
    /// struct PlayerList: View {
    ///     @ObservedObject var players: PaginatedResults<Player, Player.ID>
    ///
    ///     var body: some View {
    ///         List(players.elements) { element in
    ///             PlayerRow(player: element.value)
    ///                 .onAppear(element, prefetchIfNeeded: players)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Alternatively, you can call `prefetch` manually.
    /// See ``PaginatedElement/needsPrefetchOnAppear``.
    ///
    /// No pending page request is cancelled when this method is called.
    public func prefetch() async {
        // Don't prefetch unless there's a page to fetch.
        guard paginationState != .completed else { return }
        
        // Don't prefetch if there's an error (avoid endless loop of errors).
        guard paginationError == nil else { return }
        
        // Idle?
        guard fetchingTask == nil else { return }
        
        try? await fetchNextPage()
    }
    
    #warning("TODO: minimal delay")
    /// Refreshes the list.
    ///
    /// This method is suited for the "pull-to-refresh" gesture. The
    /// ``elements`` collection is not modified until the first page is
    /// refreshed. For example:
    ///
    /// ```swift
    /// struct PlayerList: View {
    ///     @ObservedObject var players: PaginatedResults<Player, Player.ID>
    ///     @State var presentsPaginationError: Bool = false
    ///
    ///     var body: some View {
    ///         List(players.elements) { element in
    ///             PlayerRow(player: element.value)
    ///                 .onAppear(element, prefetchIfNeeded: players)
    ///         }
    ///         .refreshable {
    ///             do {
    ///                 try await players.refresh()
    ///             } catch {
    ///                 presentsPaginationError = true
    ///             }
    ///         }
    ///         .alert(
    ///             "An Error Occurred",
    ///             isPresented: $presentsPaginationError,
    ///             presenting: players.paginationError)
    ///         { error in
    ///             Button("Cancel") { }
    ///             Button("Retry") {
    ///                 Task {
    ///                     do {
    ///                         try await players.retry(from: error)
    ///                     } catch {
    ///                         presentsPaginationError = true
    ///                     }
    ///                 }
    ///             }
    ///         } message: { error in
    ///             Text(error.localizedDescription)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Any pending page request is cancelled when this method is called.
    ///
    /// - throws: An error if the first page could not be fetched. In case of
    ///   cancellation, no error is thrown.
    public func refresh() async throws {
        fetchingTask?.cancel()
        
        let previousState = paginationState
        let task = Task {
            try await loader.refresh()
        }
        fetchingTask = task
        
        do {
            let page = try await task.value
            if fetchingTask == task {
                fetchingTask = nil
                paginationError = nil
                elements.removeAll()
                pageDidLoad(page)
            }
        } catch is CancellationError {
        } catch {
            if fetchingTask == task {
                fetchingTask = nil
                paginationState = previousState
                self.paginationError = .refresh(error)
                throw error
            }
        }
    }
    
    /// Remove all elements, and fetches the first page.
    ///
    /// Any pending page request is cancelled when this method is called.
    ///
    /// - throws: An error if the page could not be fetched. In case of
    ///   cancellation, no error is thrown.
    public func removeAllAndRefresh() async throws {
        fetchingTask?.cancel()
        
        let task = Task {
            try await loader.refresh()
        }
        fetchingTask = task
        elements.removeAll()
        paginationError = nil
        paginationState = .fetchingNextPage
        
        do {
            let page = try await task.value
            if fetchingTask == task {
                fetchingTask = nil
                paginationError = nil
                assert(elements.isEmpty)
                pageDidLoad(page)
            }
        } catch is CancellationError {
        } catch {
            if fetchingTask == task {
                fetchingTask = nil
                paginationState = .notCompleted
                self.paginationError = .refresh(error)
                throw error
            }
        }
    }
    
    /// Performs again the failed pagination action.
    ///
    /// You get the `error` argument from the ``paginationError`` property.
    public func retry(from error: PaginationError) async throws {
        switch error {
        case .fetchNextPage:
            try await fetchNextPage()
        case .refresh:
            try await refresh()
        }
    }
    
    private func pageDidLoad(_ page: Page<Element>) {
        paginationError = nil
        elements.append(page: page.elements)
        
        if page.hasNextPage {
            paginationState = .notCompleted
            if elements.count < initialElementCount {
                Task {
                    await prefetch()
                }
            }
        } else {
            paginationState = .completed
        }
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginatedResultsConfiguration {
    public var initialElementCount: Int
    public var prefetchDistance: Int
    public var maximumElementCount: Int
    
    public init(
        initialElementCount: Int = 1,
        prefetchDistance: Int = 1,
        maximumElementCount: Int = .max)
    {
        self.initialElementCount = initialElementCount
        self.prefetchDistance = prefetchDistance
        self.maximumElementCount = maximumElementCount
    }
}

/// The pagination state of a `PaginatedResults`.
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public enum PaginationState {
    /// There are pages left to fetch.
    case notCompleted
    
    /// The next page is being fetched.
    case fetchingNextPage
    
    /// There is no more page to fetch.
    case completed
}

/// A pagination error.
@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public enum PaginationError: Error {
    /// An error that occurred when fetching the next page.
    case fetchNextPage(Error)
    
    /// An error that occurred when refreshing the list.
    case refresh(Error)
    
    /// The underlying error.
    public var underlyingError: Error {
        switch self {
        case let .fetchNextPage(error), let .refresh(error):
            return error
        }
    }
    
    /// The localized description of the underlying error.
    public var localizedDescription: String {
        underlyingError.localizedDescription
    }
}
