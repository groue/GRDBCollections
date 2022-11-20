#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6, *)
public struct PaginationControl<Element, LoadingContent: View, LoadContent: View>: View {
    @ObservedObject var results: PaginatedResults<Element>
    private var loadingContent: LoadingContent
    private var loadContent: LoadContent

    public init(
        results: PaginatedResults<Element>,
        @ViewBuilder loading: () -> LoadingContent,
        @ViewBuilder load: () -> LoadContent)
    {
        self.results = results
        self.loadingContent = loading()
        self.loadContent = load()
    }
    
    public var body: some View {
        Group {
            switch results.state {
            case .loading:
                loadingContent
                
            case .completed:
                EmptyView()
                
            case .notCompleted:
                loadContent
            }
        }
    }
}
#endif
