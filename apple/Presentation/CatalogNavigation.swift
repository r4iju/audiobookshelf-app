import SwiftUI

/// Keep the same destination tree on older systems, including programmatic account routes.
struct CatalogNavigation<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if #available(iOS 16, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }.navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

extension View {
    @ViewBuilder func catalogDestination<Destination: View>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> Destination) -> some View {
        if #available(iOS 16, *) {
            navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            background(NavigationLink(destination: destination(), isActive: isPresented) { EmptyView() }.hidden())
        }
    }
}
