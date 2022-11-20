import Combine
import GRDBCollections
import SwiftUI
import os.log

struct Item: Identifiable {
    var id: Int
    var name: String
}

struct DemoDataSource: PaginationDataSource {
    var firstPageIdentifier: Int { 0 }
    var pageCount: Int
    var pageSize: Int
    var delay: Duration
    var success: () -> Bool
    
    func page(at pageIdentifier: Int) async throws -> Page<Item, Int> {
        try await Task.sleep(for: delay)
        if success() {
            let elements = (0..<pageSize).map {
                let id = Int.random(in: 0...1000)
                return Item(id: id, name: "Page \(pageIdentifier) / Item \($0)")
            }
            return Page(
                elements: elements,
                nextPageIdentifier: (pageIdentifier + 1) >= pageCount ? nil : pageIdentifier + 1)
        } else {
            throw URLError(.notConnectedToInternet)
        }
    }
}

struct PaginationDemoList: View {
    enum DemoCase: CaseIterable, Equatable, Hashable {
        case fast
        case slow
        case slowAndFlaky
        
        var localizedName: LocalizedStringKey {
            switch self {
            case .fast: return "Fast"
            case .slow: return "Slow"
            case .slowAndFlaky: return "Slow And Flaky"
            }
        }
        
        @MainActor
        var results: PaginatedResults<Item, Item.ID> {
            switch self {
            case .fast:
                return PaginatedResults(
                    dataSource: DemoDataSource(
                        pageCount: 20,
                        pageSize: 50,
                        delay: .milliseconds(100),
                        success: { true }),
                    prefetchStrategy: .minimumElementsAtBottom(50),
                    mergeStrategy: .deleteAndAppend)
                
            case .slow:
                return PaginatedResults(
                    dataSource: DemoDataSource(
                        pageCount: 20,
                        pageSize: 5,
                        delay: .seconds(1),
                        success: { true }),
                    prefetchStrategy: .minimumElementsAtBottom(10),
                    mergeStrategy: .deleteAndAppend)
                
            case .slowAndFlaky:
                return PaginatedResults(
                    dataSource: DemoDataSource(
                        pageCount: 20,
                        pageSize: 5,
                        delay: .seconds(1),
                        success: { Bool.random() }),
                    prefetchStrategy: .minimumElementsAtBottom(10),
                    mergeStrategy: .deleteAndAppend)
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
    @State var presentsError: Bool = false
    
    var body: some View {
        ScrollViewReader { scrollView in
            List {
                ForEach(results.elements) { paginatedElement in
                    ItemRow(item: paginatedElement.element)
                        .onAppear(perform: paginatedElement.prefetchIfNeeded)
                        .id(paginatedElement.id)
                }
                
                switch results.state {
                case .loadingNextPage:
                    loadingView
                case .completed:
                    EmptyView()
                case .notCompleted:
                    loadNextPageButton
                }
            }
            
            .refreshable {
                do {
                    try await results.refresh()
                } catch {
                    presentsError = true
                }
            }
            
            .alert("An Error Occurred", isPresented: $presentsError, presenting: results.error) { error in
                Button(role: .cancel) { } label: { Text("Cancel") }
                retryButton(from: error)
            } message: { Text($0.localizedDescription) }
        
            .toolbar {
                Button {
                    Task {
                        do {
                            try await results.refresh()
                            if let id = results.elements.first?.id {
                                scrollView.scrollTo(id)
                            }
                        } catch {
                            presentsError = true
                        }
                    }
                } label: { Text("Refresh") }
            }
        }
    }
    
    var loadingView: some View {
        Text("Loading…")
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(.secondary)
    }
    
    var loadNextPageButton: some View {
        Button {
            Task {
                do {
                    try await results.fetchNextPage()
                } catch {
                    presentsError = true
                }
            }
        } label: {
            VStack(alignment: .center) {
                if let error = results.error {
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.leading)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                Text("Load Next Page")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    func retryButton(from error: PaginationError) -> some View {
        Button {
            Task {
                switch error {
                case .refresh:
                    do {
                        try await results.refresh()
                    } catch {
                        presentsError = true
                    }
                case .nextPage:
                    do {
                        try await results.fetchNextPage()
                    } catch {
                        presentsError = true
                    }
                }
            }
        } label: { Text("Retry") }
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
