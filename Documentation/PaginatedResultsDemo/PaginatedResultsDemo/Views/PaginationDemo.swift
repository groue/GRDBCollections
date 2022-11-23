import Combine
import GRDBCollections
import SwiftUI
import os.log

struct Item: Identifiable {
    var id: Int
    var name: String
}

struct DemoPaginationSource: PageSource {
    func firstPageIdentifier() -> Int? { 0 }
    
    /// The number of pages
    var pageCount: Int
    
    /// The number of items per page
    var pageSize: Int
    
    /// The number of items with a reused id in a page
    var overlap: Int
    
    /// The delay before the page is produced
    var delay: Duration
    
    /// A closure that can prevent the page from being produced by throwing an error
    var check: (() throws -> Void)?
    
    func page(at pageIdentifier: Int) async throws -> (elements: [Item], nextPageIdentifier: Int?) {
        try await Task.sleep(for: delay)
        try check?()
        let elements = (0..<pageSize).map { index in
            let id = pageIdentifier * (pageSize - overlap) + index
            return Item(id: id, name: "Page \(pageIdentifier) / Item \(index)")
        }
        return (
            elements: elements,
            nextPageIdentifier: (pageIdentifier + 1) >= pageCount ? nil : pageIdentifier + 1)
    }
}

struct PaginationDemoList: View {
    enum DemoCase: CaseIterable, Equatable, Hashable {
        case fast
        case slowOverlap
        case slowAndFlaky
        
        var localizedName: LocalizedStringKey {
            switch self {
            case .fast: return "Fast"
            case .slowOverlap: return "Slow + Overlap"
            case .slowAndFlaky: return "Slow And Flaky"
            }
        }
        
        @MainActor
        var results: PaginatedResults<Item, Item.ID> {
            switch self {
            case .fast:
                return PaginatedResults(
                    DemoPaginationSource(
                        pageCount: 20,
                        pageSize: 50,
                        overlap: 0,
                        delay: .milliseconds(100)),
                    prefetchDistance: 50)
                
            case .slowOverlap:
                return PaginatedResults(
                    DemoPaginationSource(
                        pageCount: 6,
                        pageSize: 10,
                        overlap: 2,
                        delay: .seconds(1)),
                    prefetchDistance: 5)
                
            case .slowAndFlaky:
                return PaginatedResults(
                    DemoPaginationSource(
                        pageCount: 6,
                        pageSize: 5,
                        overlap: 0,
                        delay: .seconds(1),
                        check: {
                            if Bool.random() {
                                throw URLError(.notConnectedToInternet)
                            }
                        }),
                    prefetchDistance: 5)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List(DemoCase.allCases, id: \.self) { demoCase in
                NavigationLink(demoCase.localizedName, value: demoCase)
            }
            .navigationDestination(for: DemoCase.self) { demoCase in
                PaginationDemoView(results: demoCase.results)
                    .navigationTitle(demoCase.localizedName)
            }
            .navigationTitle("Pagination Demos")
        }
    }
}

struct PaginationDemoView: View {
    @StateObject var results: PaginatedResults<Item, Item.ID>
    @State var presentsPaginationError: Bool = false
    
    var body: some View {
        List {
            Section {
                ForEach(results.elements) { element in
                    ItemRow(item: element.value)
                        .onAppear(element, prefetchIfNeeded: results)
                }
            } footer: {
                switch results.paginationState {
                case .fetchingNextPage:
                    loadingView
                case .completed:
                    completedView
                case .notCompleted:
                    fetchNextPageButton
                }
            }
        }
        
        .refreshable {
            do {
                try await results.refresh()
            } catch {
                presentsPaginationError = true
            }
        }
        
        .alert(
            "An Error Occurred",
            isPresented: $presentsPaginationError,
            presenting: results.paginationError)
        { error in
            Button("Cancel") { }
            retryButton(from: error)
        } message: { error in
            Text(error.localizedDescription)
        }
        
        .toolbar {
            if results.isFetchingPage {
                ProgressView().progressViewStyle(.circular)
            }
            
            Button {
                Task {
                    do {
                        try await results.removeAllAndRefresh()
                    } catch {
                        presentsPaginationError = true
                    }
                }
            } label: { Text("Refresh") }
        }
    }
    
    var completedView: some View {
        Text("End of List")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(.secondary)
    }
    
    var loadingView: some View {
        Text("Loading…")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(.secondary)
    }
    
    var fetchNextPageButton: some View {
        Button {
            Task {
                do {
                    try await results.fetchNextPage()
                } catch {
                    presentsPaginationError = true
                }
            }
        } label: {
            VStack(alignment: .center) {
                if let error = results.paginationError {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.leading)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .foregroundColor(.primary)
                        .padding(.bottom, 4)
                }
                Text("Load Next Page")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    func retryButton(from error: PaginationError) -> some View {
        Button("Retry") {
            Task {
                do {
                    try await results.retry(from: error)
                } catch {
                    presentsPaginationError = true
                }
            }
        }
    }
}

struct ItemRow: View {
    let item: Item
    
    var body: some View {
        HStack {
            Text(item.name)
            Spacer()
            Text("ID \(item.id)")
                .foregroundStyle(.secondary)
        }
    }
}
