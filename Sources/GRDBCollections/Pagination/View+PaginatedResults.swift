#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension View {
    /// Prefetches the next page of `results` before this view appears,
    /// according to the prefetch strategy.
    ///
    /// For example:
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
    @ViewBuilder
    public func onAppear<Element, ID: Hashable>(
        _ element: PaginatedElement<Element, ID>,
        prefetchIfNeeded results: PaginatedResults<Element, ID>)
    -> some View
    {
        if element.needsPrefetchOnAppear {
            // Force a new id so that onAppear is triggered.
            self
                .id(UUID())
                .onAppear {
                    Task {
                        await results.prefetch()
                    }
                }
        } else {
            self
        }
    }
}
#endif
