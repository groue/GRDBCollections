#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
extension View {
    @ViewBuilder
    public func fetchNextPageIfNeeded<Element, ID: Hashable>(from element: PaginatedElement<Element, ID>) -> some View {
        if let prefetch = element.prefetch {
            // Force a new id so that onAppear is triggered.
            self
                .id(UUID())
                .onAppear(perform: prefetch)
        } else {
            self
        }
    }
}
#endif
