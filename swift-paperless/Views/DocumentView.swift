//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import QuickLook
import SwiftUI

struct SearchFilterBar<Content: View>: View {
    @Environment(\.isSearching) private var isSearching

    var content: () -> Content

    var body: some View {
        if isSearching {
            content()
        }
    }
}

struct DocumentView: View {
    @StateObject private var store = DocumentStore()

    @StateObject var searchDebounce = DebounceObject(delay: 0.1)

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    @State var initialLoad = true

    @State var isLoading = false

    @State var filterState = FilterState()

    func load(clear: Bool, setLoading _setLoading: Bool = true) async {
        if _setLoading { await setLoading(to: true) }
        async let _ = await store.fetchAllCorrespondents()
        async let _ = await store.fetchAllDocumentTypes()
        print("Load: \(store.filterState)")
        await store.fetchDocuments(clear: clear)
        print("Load complete")
        if _setLoading { await setLoading(to: false) }
    }

    func updateSearchCompletion() async {
        if searchDebounce.debouncedText == "" {
            searchSuggestions = []
        }
        else {
            searchSuggestions = await getSearchCompletion(term: searchDebounce.debouncedText)
        }
    }

    func handleSearch(query: String) async {
        var filterState = store.filterState
        filterState.searchText = query == "" ? nil : query
        store.filterState = filterState

        await setLoading(to: true)
        await load(clear: true)
        await setLoading(to: false)
    }

    func setLoading(to value: Bool) async {
        withAnimation {
            isLoading = value
        }
    }

    func scrollToTop(scrollView: ScrollViewProxy) {
        if store.documents.count > 0 {
            withAnimation {
                scrollView.scrollTo(store.documents[0].id, anchor: .top)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollView in
                ScrollView {
                    if isLoading {
                        ProgressView()
                            .padding(15)
                            .scaleEffect(2)
                            .transition(.opacity)
                    }
                    LazyVStack(alignment: .leading) {
                        ForEach($store.documents, id: \.id) { $document in
                            NavigationLink(destination: {
                                DocumentDetailView(document: $document)
                                    .navigationBarTitleDisplayMode(.inline)
                            }, label: {
                                DocumentCell(document: document).task {
                                    let index = store.documents.firstIndex { $0 == document }
                                    if index == store.documents.count - 10 {
//                                    if document == store.documents.last {
                                        Task {
                                            await load(clear: false, setLoading: false)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                            })
                            .buttonStyle(.plain)
                            .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
                        }
                    }
                    if store.documents.isEmpty && !isLoading && !initialLoad {
                        Text("No documents found")
                            .foregroundColor(.gray)
                            .transition(.opacity)
                    }
                }
                .clipped()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showFilterModal.toggle() }) {
                            Label("Filter", systemImage:
                                store.filterState.filtering ?
                                    "line.3.horizontal.decrease.circle.fill" :
                                    "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .navigationTitle("Documents")

                .refreshable {
                    Task {
                        await load(clear: true)
                    }
                }

                .animation(.default, value: store.documents)

                .sheet(isPresented: $showFilterModal, onDismiss: {
//                    if filterState != store.filterState {
//                        print("Filter updated \(filterState)")
//                        Task {
//                            store.filterState = filterState
//                            scrollToTop(scrollView: scrollView)
//                        }
//                    }
//                    else {
//                        print("Filter state not updated")
//                    }
                }) {
                    FilterView(filterState: store.filterState)
                        .environmentObject(store)
                }

                .onChange(of: store.filterState) { _ in
                    print("Filter updated \(store.filterState)")
                    Task {
                        store.clearDocuments()
                        await load(clear: true)
                    }
                }

                .task {
                    if initialLoad {
                        await load(clear: true)
                        initialLoad = false
                    }
                }

                .onChange(of: searchDebounce.debouncedText) { _ in
                    if searchDebounce.debouncedText == "" {
                        scrollToTop(scrollView: scrollView)
                    }
                    Task {
                        await updateSearchCompletion()

                        print("Change search to \(searchDebounce.debouncedText)")

                        if searchDebounce.debouncedText == "" {
                            store.filterState.searchText = nil
                            await load(clear: true)
                        }
                    }
                }

                SearchFilterBar {
                    Button(action: { showFilterModal.toggle() }) {
                        Label("Filter", systemImage:
                            store.filterState.filtering ?
                                "line.3.horizontal.decrease.circle.fill" :
                                "line.3.horizontal.decrease.circle")
                    }.padding(10)
                }
            }
        }
        .searchable(text: $searchDebounce.text,
                    placement: .automatic) {
            ForEach(searchSuggestions, id: \.self) { v in
                Text(v).searchCompletion(v)
            }
        }
        .onSubmit(of: .search) {
            print("Search submit: \(searchDebounce.text)")
            if searchDebounce.text == store.filterState.searchText {
                return
            }
//            scrollToTop(scrollView: scrollView)
            Task {
                store.filterState.searchText = searchDebounce.text
                await load(clear: true)
            }
        }

        .environmentObject(store)
    }
}
