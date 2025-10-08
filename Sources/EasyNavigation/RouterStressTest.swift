import SwiftUI

/// A stress test view for testing Router performance and memory management
/// Use this view to test navigation handling under heavy load
public struct RouterStressTest: View {
    /// Initialize a new router stress test view
    @State var stack = RouterStack()
    public init() {}
    
    public var body: some View {
        StressTestTabView()
            .environment(stack)
            .background(Color(.systemBackground)) // Prevent transparency issues
    }
}

private struct StressTestTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ViewNavigationWrapper {
                NavigationStressTest()
                    .background(Color(.systemBackground))
            }
            .tabItem {
                Label("Navigation", systemImage: "arrow.right")
            }
            .tag(0)
            
            ViewNavigationWrapper {
                SheetStressTest()
                    .background(Color(.systemBackground))
            }
            .tabItem {
                Label("Sheets", systemImage: "rectangle.portrait")
            }
            .tag(1)
            
            ViewNavigationWrapper {
                FullscreenStressTest()
                    .background(Color(.systemBackground))
            }
            .tabItem {
                Label("Fullscreen", systemImage: "rectangle.fill")
            }
            .tag(2)
            
            ViewNavigationWrapper {
                MixedStressTest()
                    .background(Color(.systemBackground))
            }
            .tabItem {
                Label("Mixed", systemImage: "arrow.triangle.merge")
            }
            .tag(3)
            
            ViewNavigationWrapper {
                AdvancedNavigationDemo()
                    .background(Color(.systemBackground))
            }
            .tabItem {
                Label("Advanced", systemImage: "wand.and.stars")
            }
            .tag(4)
        }
        .background(Color(.systemBackground))
    }
}

// Stress test for navigation stack pushing/popping
private struct NavigationStressTest: View {
    @Environment(Router.self) private var router
    @State private var depth = 0
    @State private var maxDepth = 20
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Navigation Stress Test")
                    .font(.title)
                    .padding(.top)
                
                Text("Current Depth: \(depth)")
                    .font(.headline)
                    .id(UUID()) // Prevent layout issues from frequent updates
                
                Stepper("Max Depth: \(maxDepth)", value: $maxDepth, in: 5...100)
                    .padding(.horizontal)
                
                Button(isRunning ? "Stop Test" : "Start Test") {
                    if isRunning {
                        stopTest()
                    } else {
                        startNavigationTest()
                    }
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: 200)
                .background(isRunning ? Color.red : Color.blue)
                .cornerRadius(10)
                
                Button("Push Once") {
                    pushView()
                }
                .buttonStyle(.bordered)
                .disabled(isRunning)
                .padding()
                .frame(maxWidth: 200)
                
                Button("Pop To Root") {
                    router.popToRoot()
                    depth = 0
                }
                .buttonStyle(.bordered)
                .disabled(depth == 0)
                .padding()
                .frame(maxWidth: 200)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
    
    private func startNavigationTest() {
        isRunning = true
        depth = 0 // Reset when starting
        timerTask = Task { @MainActor in
            while !Task.isCancelled && isRunning {
                if depth < maxDepth {
                    pushView()
                } else {
                    stopTest()
                    depth = 0
                }
            }
        }
    }
    
    private func pushView() {
        guard depth < maxDepth else {
            return
        }
        
        depth += 1
        router.push {
            NestedView(depth: depth, maxDepth: maxDepth)
        }
    }
    
    private func stopTest() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }
}

private struct NestedView: View {
    @Environment(Router.self) private var router
    let depth: Int
    let maxDepth: Int
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Depth: \(depth)/\(maxDepth)")
                .font(.title)
                .padding()
            
            Button("Pop") {
                router.pop()
            }
            .buttonStyle(.bordered)
            .padding()
            .frame(width: 150, height: 44)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(8)
            
            Button("Pop To Root") {
                router.popToRoot()
            }
            .buttonStyle(.bordered)
            .padding()
            .frame(width: 150, height: 44)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hue: Double(depth) / Double(maxDepth), saturation: 0.8, brightness: 0.9))
    }
}

// Stress test for sheets
private struct SheetStressTest: View {
    @Environment(Router.self) private var router
    @State private var sheetCount = 0
    @State private var maxSheets = 10
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Button("Present Sheet") {
                    presentSheet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .padding()
                .frame(width: 200, height: 50)
                .background(Color.blue.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: 2)
                )
                
                Text("Sheet Stress Test")
                    .font(.title)
                
                Text("Sheets Opened: \(sheetCount)")
                    .font(.headline)
                    .id(UUID()) // Prevent layout issues
                
                Stepper("Max Sheets: \(maxSheets)", value: $maxSheets, in: 5...50)
                    .padding(.horizontal)
                
                Button(isRunning ? "Stop Test" : "Start Test") {
                    if isRunning {
                        stopTest()
                    } else {
                        startSheetTest()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(width: 200, height: 50)
                .background(isRunning ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
    
    private func startSheetTest() {
        isRunning = true
        sheetCount = 0 // Reset on start
        timerTask = Task { @MainActor in
            while !Task.isCancelled && isRunning {
                if sheetCount < maxSheets {
                    presentSheet()
                } else {
                    // When reached max, stop test
                    stopTest()
                    break
                }
            }
        }
    }
    
    private func presentSheet() {
        guard sheetCount < maxSheets else {
            stopTest()
            return
        }
        
        sheetCount += 1
        router.sheet {
            SheetView(number: sheetCount, maxSheets: maxSheets)
        }
    }
    
    private func stopTest() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }
}

private struct SheetView: View {
    @Environment(Router.self) private var router
    @Environment(NavigationInformations.self) private var navInfo
    @Environment(RouterStack.self) private var routerStack
    let number: Int
    let maxSheets: Int
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Sheet \(number)/\(maxSheets)")
                .font(.title)
                .padding(.top, 30)
            
            Text("Navigation Type: \(String(describing: navInfo.navigationType))")
                .font(.caption)
            
            Button("Dismiss") {
                router.dismiss()
            }
            .buttonStyle(.bordered)
            .padding()
            .frame(width: 150, height: 44)
            .background(Color.red.opacity(0.2))
            .cornerRadius(8)
            
            if number < maxSheets {
                Button("Present Another Sheet") {
                    router.sheet {
                        SheetView(number: number + 1, maxSheets: maxSheets)
                            .environment(routerStack) // Ensure RouterStack is passed along
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(width: 250, height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hue: Double(number) / Double(maxSheets), saturation: 0.7, brightness: 0.9))
        .onAppear {
            print("SheetView appeared: number=\(number)")
        }
    }
}

// Stress test for fullscreen presentations
private struct FullscreenStressTest: View {
    @Environment(Router.self) private var router
    @State private var presentationCount = 0
    @State private var maxPresentations = 10
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Fullscreen Stress Test")
                    .font(.title)
                    .padding(.top)
                
                Text("Presentations: \(presentationCount)")
                    .font(.headline)
                    .id(UUID()) // Prevent layout issues
                
                Stepper("Max Presentations: \(maxPresentations)", value: $maxPresentations, in: 5...50)
                    .padding(.horizontal)
                
                Button(isRunning ? "Stop Test" : "Start Test") {
                    if isRunning {
                        stopTest()
                    } else {
                        startFullscreenTest()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(width: 200, height: 50)
                .background(isRunning ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Present Fullscreen") {
                    presentFullscreen()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .padding()
                .frame(width: 200, height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
    
    private func startFullscreenTest() {
        isRunning = true
        presentationCount = 0 // Reset on start
        timerTask = Task { @MainActor in
            while !Task.isCancelled && isRunning {
                if presentationCount < maxPresentations {
                    presentFullscreen()
                } else {
                    // When reached max, stop test
                    stopTest()
                    break
                }
            }
        }
    }
    
    private func presentFullscreen() {
        guard presentationCount < maxPresentations else {
            stopTest()
            return
        }
        
        presentationCount += 1
        router.present {
            FullscreenView(number: presentationCount, maxPresentations: maxPresentations)
        }
    }
    
    private func stopTest() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }
}

private struct FullscreenView: View {
    @Environment(Router.self) private var router
    @Environment(NavigationInformations.self) private var navInfo
    @Environment(RouterStack.self) private var routerStack
    let number: Int
    let maxPresentations: Int
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Fullscreen \(number)/\(maxPresentations)")
                .font(.title)
                .padding(.top, 30)
            
            Text("Navigation Type: \(String(describing: navInfo.navigationType))")
                .font(.caption)
            
            Button("Dismiss") {
                router.dismiss()
            }
            .buttonStyle(.bordered)
            .padding()
            .frame(width: 150, height: 44)
            .background(Color.red.opacity(0.2))
            .cornerRadius(8)
            
            if number < maxPresentations {
                Button("Present Another Fullscreen") {
                    router.present {
                        FullscreenView(number: number + 1, maxPresentations: maxPresentations)
                            .environment(routerStack) // Ensure RouterStack is passed along
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(width: 250, height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hue: Double(number) / Double(maxPresentations), saturation: 0.6, brightness: 0.9))
        .onAppear {
            print("FullscreenView appeared: number=\(number)")
        }
    }
}

// Mixed stress test combining different navigation types
private struct MixedStressTest: View {
    @Environment(Router.self) private var router
    @State private var operationCount = 0
    @State private var maxOperations = 30
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?
    @Environment(NavigationInformations.self) private var navInfo
    @Environment(RouterStack.self) private var routerStack // Get RouterStack from environment
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Mixed Stress Test")
                    .font(.title)
                    .padding(.top)
                
                Text("Operations: \(operationCount)/\(maxOperations)")
                    .font(.headline)
                    .id(UUID()) // Prevent redraws due to operationCount changes affecting layout
                
                Stepper("Max Operations: \(maxOperations)", value: $maxOperations, in: 10...100)
                    .padding(.horizontal)
                
                Button(isRunning ? "Stop Test" : "Start Test") {
                    if isRunning {
                        stopTest()
                    } else {
                        startMixedTest()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(width: 200, height: 50)
                .background(isRunning ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Random Operation") {
                    performRandomOperation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .padding()
                .frame(width: 200, height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button("Reset") {
                    router.popToRoot()
                    operationCount = 0
                }
                .buttonStyle(.bordered)
                .padding()
                .frame(width: 200, height: 50)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
    
    private func startMixedTest() {
        isRunning = true
        operationCount = 0 // Reset counter when starting
        timerTask = Task { @MainActor in
            while !Task.isCancelled && isRunning {
                if operationCount < maxOperations {
                    performRandomOperation()
                } else {
                    // When we reach max operations, reset and stop the test
                    router.popToRoot()
                    operationCount = 0
                    stopTest()
                    break
                }
            }
        }
    }
    
    private func performRandomOperation() {
        guard operationCount < maxOperations else {
            stopTest()
            return
        }
        
        operationCount += 1
        let operation = Int.random(in: 0...3)
        
        switch operation {
        case 0:
            router.push {
                MixedNestedView(count: operationCount, maxCount: maxOperations)
                    .environment(routerStack) // Pass RouterStack to new view
            }
        case 1:
            router.sheet {
                MixedNestedView(count: operationCount, maxCount: maxOperations)
                    .environment(routerStack) // Pass RouterStack to new view
            }
        case 2:
            router.present {
                MixedNestedView(count: operationCount, maxCount: maxOperations)
                    .environment(routerStack) // Pass RouterStack to new view
            }
        case 3:
            if navInfo.isPushed {
                router.pop()
            } else {
                router.dismiss()
            }
        default:
            break
        }
    }
    
    private func stopTest() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }
}

private struct MixedNestedView: View {
    @Environment(Router.self) private var router
    @Environment(NavigationInformations.self) private var navInfo
    @Environment(RouterStack.self) private var routerStack
    let count: Int
    let maxCount: Int
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Operation \(count)/\(maxCount)")
                .font(.title)
                .padding(.top, 20)
            
            Text("Type: \(String(describing: navInfo.navigationType))")
            Text("Is Pushed: \(navInfo.isPushed ? "Yes" : "No")")
            Text("Is Presenting: \(navInfo.isPresented ? "Yes" : "No")")
            
            Button("Dismiss/Pop") {
                if navInfo.isPushed {
                    router.pop()
                } else {
                    router.dismiss()
                }
            }
            .buttonStyle(.bordered)
            .padding()
            .frame(width: 150, height: 44)
            .background(Color.red.opacity(0.2))
            .cornerRadius(8)
            
            if count < maxCount - 5 {
                Button("Random Next Operation") {
                    performRandomOperation()
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(width: 250, height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hue: Double(count) / Double(maxCount), saturation: 0.8, brightness: 0.9))
        .onAppear {
            print("MixedNestedView appeared: count=\(count), type=\(navInfo.navigationType)")
        }
    }
    
    private func performRandomOperation() {
        let operation = Int.random(in: 0...2)
        
        switch operation {
        case 0:
            router.push {
                MixedNestedView(count: count + 1, maxCount: maxCount)
                    .environment(routerStack) // Pass RouterStack to new view
            }
        case 1:
            router.sheet {
                MixedNestedView(count: count + 1, maxCount: maxCount)
                    .environment(routerStack) // Pass RouterStack to new view
            }
        case 2:
            router.present {
                MixedNestedView(count: count + 1, maxCount: maxCount)
                    .environment(routerStack) // Pass RouterStack to new view
            }
        default:
            break
        }
    }
}

// Advanced navigation demo for testing various router operations
private struct AdvancedNavigationDemo: View {
    @Environment(Router.self) private var router
    @Environment(RouterStack.self) private var routerStack
    @Environment(NavigationInformations.self) private var navInfo
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Advanced Navigation Demo")
                    .font(.title)
                    .padding(.top)
                
                // Debugging info
                VStack(alignment: .leading, spacing: 5) {
                    Text("Navigation Path Count: \(router.path.count)")
                        .font(.caption)
                    Text("Is Root: \(String(describing: navInfo.navigationType == .root))")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 5)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                // Push and remove self section
                GroupBox(label: Label("Push and Remove Self", systemImage: "arrow.right.doc.on.clipboard")) {
                    VStack(spacing: 16) {
                        Button("Push and Remove Self") {
                            print("Before pushAndRemoveSelf - Path count: \(router.path.count)")
                            router.pushAndRemoveSelf {
                                NextDemoView(title: "PushAndRemoveSelf View", number: 1)
                                    .environment(routerStack)
                            }
                            // Add a small delay to print after the operation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                print("After pushAndRemoveSelf - Path count: \(router.path.count)")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Standard push section
                GroupBox(label: Label("Regular Push", systemImage: "arrow.right")) {
                    VStack(spacing: 16) {
                        Button("Regular Push") {
                            print("Before push - Path count: \(router.path.count)")
                            router.push {
                                NextDemoView(title: "Regular Push View", number: 1)
                                    .environment(routerStack)
                            }
                            // Add a small delay to print after the operation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                print("After push - Path count: \(router.path.count)")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Push and remove all section
                GroupBox(label: Label("Push and Remove All", systemImage: "arrow.triangle.2.circlepath")) {
                    VStack(spacing: 16) {
                        Button("Push and Remove All") {
                            print("Before pushAndRemoveAll - Path count: \(router.path.count)")
                            router.pushAndRemoveAll {
                                NextDemoView(title: "PushAndRemoveAll View", number: 1)
                                    .environment(routerStack)
                            }
                            // Add a small delay to print after the operation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                print("After pushAndRemoveAll - Path count: \(router.path.count)")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Presentation options section
                GroupBox(label: Label("Presentation Options", systemImage: "square.on.square")) {
                    VStack(spacing: 16) {
                        Button("Present Fullscreen") {
                            router.present {
                                PresentationDemoView(title: "Fullscreen View", presentationType: "Fullscreen")
                                    .environment(routerStack)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        
                        Button("Present Sheet") {
                            router.sheet {
                                PresentationDemoView(title: "Sheet View", presentationType: "Sheet")
                                    .environment(routerStack)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Chained operations section
                GroupBox(label: Label("Chained Operations", systemImage: "link")) {
                    VStack(spacing: 16) {
                        Button("Push → Present → Sheet") {
                            router.push {
                                NextDemoView(title: "Pushed View", number: 1,
                                             nextAction: {
                                    router.present {
                                        PresentationDemoView(title: "Presented After Push",
                                                             presentationType: "Fullscreen",
                                                             nextAction: {
                                            router.sheet {
                                                PresentationDemoView(title: "Sheet After Present",
                                                                     presentationType: "Sheet")
                                                .environment(routerStack)
                                            }
                                        })
                                        .environment(routerStack)
                                    }
                                })
                                .environment(routerStack)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
            .onAppear {
                print("AdvancedNavigationDemo appeared - Path count: \(router.path.count)")
            }
        }
    }
}

private struct NextDemoView: View {
    @Environment(Router.self) private var router
    @Environment(NavigationInformations.self) private var navInfo
    @Environment(RouterStack.self) private var routerStack
    
    let title: String
    let number: Int
    var nextAction: (() -> Void)? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(title)
                    .font(.title)
                    .padding(.top, 20)
                
                // Debugging info
                VStack(alignment: .leading, spacing: 5) {
                    Text("Navigation Path Count: \(router.path.count)")
                        .font(.caption)
                    Text("Navigation Type: \(String(describing: navInfo.navigationType))")
                        .font(.caption)
                    Text("Is Pushed: \(navInfo.isPushed ? "Yes" : "No")")
                        .font(.caption)
                    Text("Is Presented: \(navInfo.isPresented ? "Yes" : "No")")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 5)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                Button("Go Back") {
                    if navInfo.isPushed {
                        router.pop()
                    } else {
                        router.dismiss()
                    }
                }
                .buttonStyle(.bordered)
                .padding()
                
                if nextAction != nil {
                    Button("Continue to Next Screen") {
                        nextAction?()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                
                Button("Push Next View") {
                    print("Before push from NextDemoView - Path count: \(router.path.count)")
                    router.push {
                        NextDemoView(title: "Pushed View", number: number + 1)
                            .environment(routerStack)
                    }
                    // Add a small delay to print after the operation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("After push from NextDemoView - Path count: \(router.path.count)")
                    }
                }
                .buttonStyle(.bordered)
                .padding()
                
                Button("Push and Remove Self") {
                    print("Before pushAndRemoveSelf from NextDemoView - Path count: \(router.path.count)")
                    router.pushAndRemoveSelf {
                        NextDemoView(title: "PushAndRemoveSelf View", number: number + 1)
                            .environment(routerStack)
                    }
                    // Add a small delay to print after the operation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("After pushAndRemoveSelf from NextDemoView - Path count: \(router.path.count)")
                    }
                }
                .buttonStyle(.bordered)
                .padding()
                
                Button("Push and Remove All") {
                    print("Before pushAndRemoveAll from NextDemoView - Path count: \(router.path.count)")
                    router.pushAndRemoveAll {
                        NextDemoView(title: "PushAndRemoveAll View", number: number + 1)
                            .environment(routerStack)
                    }
                    // Add a small delay to print after the operation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("After pushAndRemoveAll from NextDemoView - Path count: \(router.path.count)")
                    }
                }
                .buttonStyle(.bordered)
                .padding()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(hue: Double(number) * 0.1, saturation: 0.3, brightness: 0.95))
            .onAppear {
                print("NextDemoView appeared: \(title) - Path count: \(router.path.count)")
            }
        }
    }
}

private struct PresentationDemoView: View {
    @Environment(Router.self) private var router
    @Environment(NavigationInformations.self) private var navInfo
    @Environment(RouterStack.self) private var routerStack
    
    let title: String
    let presentationType: String
    var nextAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title)
                .padding(.top, 20)
            
            Text("Presentation Type: \(presentationType)")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Navigation Info:")
                    .font(.headline)
                
                Text("Is Pushed: \(navInfo.isPushed ? "Yes" : "No")")
                Text("Is Presented: \(navInfo.isPresented ? "Yes" : "No")")
                Text("Navigation Type: \(String(describing: navInfo.navigationType))")
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Button("Dismiss") {
                router.dismiss()
            }
            .buttonStyle(.bordered)
            .padding()
            
            if nextAction != nil {
                Button("Continue to Next Screen") {
                    nextAction?()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            
            Button("Present Fullscreen") {
                router.present {
                    PresentationDemoView(title: "New Fullscreen", presentationType: "Fullscreen")
                        .environment(routerStack)
                }
            }
            .buttonStyle(.bordered)
            .padding()
            
            Button("Present Sheet") {
                router.sheet {
                    PresentationDemoView(title: "New Sheet", presentationType: "Sheet")
                        .environment(routerStack)
                }
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            presentationType == "Sheet"
            ? Color.blue.opacity(0.1)
            : Color.green.opacity(0.1)
        )
    }
}
