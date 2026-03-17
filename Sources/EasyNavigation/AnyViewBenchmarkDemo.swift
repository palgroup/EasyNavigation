//
//  AnyViewBenchmarkDemo.swift
//  EasyNavigation
//
//  Proof-of-concept: AnyView + .id(UUID()) vs Concrete View body evaluation benchmark.
//  Shows how AnyView + .id() causes unnecessary full hierarchy rebuilds.
//
//  HOW TO USE:
//  1. Put `AnyViewBenchmarkDemo()` or `IdDestructionProof()` in your dev menu
//  2. Tap "State Degistir" and watch Xcode console
//  3. AnyView side: ALL levels' body is called (5 body calls for 5 levels)
//  4. Concrete side: ONLY the deepest level's body is called (1 body call)
//
//  This proves SwiftUI's structural identity optimization is broken by AnyView + .id(UUID()).
//

import SwiftUI

// MARK: - Global counters (MainActor-isolated)

@MainActor
private final class BodyCounter {
    static let shared = BodyCounter()

    var anyViewCounts: [Int: Int] = [:]
    var concreteCounts: [Int: Int] = [:]
    var anyViewTotalRebuilds: Int = 0
    var concreteTotalRebuilds: Int = 0

    // Timing
    var anyViewLastRenderTime: Double = 0
    var concreteLastRenderTime: Double = 0
    private var anyViewRenderStart: Double = 0
    private var concreteRenderStart: Double = 0

    func reset() {
        anyViewCounts = [:]
        concreteCounts = [:]
        anyViewTotalRebuilds = 0
        concreteTotalRebuilds = 0
        anyViewLastRenderTime = 0
        concreteLastRenderTime = 0
    }

    func startAnyViewTiming() { anyViewRenderStart = CFAbsoluteTimeGetCurrent() }
    func endAnyViewTiming() { anyViewLastRenderTime = (CFAbsoluteTimeGetCurrent() - anyViewRenderStart) * 1000 }

    func startConcreteTiming() { concreteRenderStart = CFAbsoluteTimeGetCurrent() }
    func endConcreteTiming() { concreteLastRenderTime = (CFAbsoluteTimeGetCurrent() - concreteRenderStart) * 1000 }

    func recordAnyView(depth: Int) {
        anyViewCounts[depth, default: 0] += 1
        anyViewTotalRebuilds += 1
    }

    func recordConcrete(depth: Int) {
        concreteCounts[depth, default: 0] += 1
        concreteTotalRebuilds += 1
    }
}

// MARK: - Public Demo Entry Point

/// Benchmark demo that proves AnyView + .id(UUID()) causes unnecessary body re-evaluations.
///
/// Place this in your dev menu:
/// ```swift
/// NavigationLink("AnyView Benchmark") {
///     AnyViewBenchmarkDemo()
/// }
/// ```
///
/// Two additional standalone proofs are also available:
/// - `IdDestructionProof()` — proves .id(UUID()) destroys/recreates views
/// - `AnyViewVsConcreteProof()` — proves AnyView blocks structural diffing
public struct AnyViewBenchmarkDemo: View {
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedTab) {
                Text("Side-by-Side").tag(0)
                Text(".id() Proof").tag(1)
                Text("AnyView Proof").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case 0:
                SideBySideTab()
            case 1:
                IdDestructionProof()
            default:
                AnyViewVsConcreteProof()
            }
        }
        .navigationTitle("AnyView Benchmark")
        .onAppear {
            BodyCounter.shared.reset()
        }
    }
}

// MARK: - Side-by-Side Benchmark

/// The main proof: 5 views stacked. Only the deepest one's data changes.
/// - AnyView + .id(UUID()): ALL 5 views' body called (forced destruction)
/// - Concrete (no .id()): ONLY 1 view's body called (the one that changed)
private struct SideBySideTab: View {
    @State private var triggerCount = 0
    @State private var depth = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Explanation
                VStack(spacing: 4) {
                    Text("\(depth) view stacked. Sadece en derin view'in state'i degisiyor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Console'u izle: kac tane body cagriliyor?")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }

                Stepper("Derinlik: \(depth)", value: $depth, in: 2...15)
                    .padding(.horizontal)

                // Side by side stacks
                HStack(alignment: .top, spacing: 8) {
                    // LEFT: AnyView + .id(UUID())
                    VStack(spacing: 4) {
                        Label("AnyView+.id()", systemImage: "xmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.red)

                        AnyViewStack(maxDepth: depth, triggerCount: triggerCount)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    // RIGHT: Concrete, no .id()
                    VStack(spacing: 4) {
                        Label("Concrete", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)

                        ConcreteStack(maxDepth: depth, triggerCount: triggerCount)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)

                // Results
                resultsCard

                // Actions
                VStack(spacing: 8) {
                    Button {
                        // Reset counters BEFORE triggering, so we only measure THIS render pass
                        BodyCounter.shared.reset()
                        BodyCounter.shared.startAnyViewTiming()
                        BodyCounter.shared.startConcreteTiming()

                        print("\n" + String(repeating: "=", count: 70))
                        print("  BENCHMARK: trigger \(triggerCount) → \(triggerCount + 1)")
                        print("  Derinlik: \(depth) view")
                        print("  Sadece en derin view (depth=\(depth - 1)) state degisiyor")
                        print(String(repeating: "-", count: 70))
                        triggerCount += 1
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("State Degistir")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button("Sayaclari Sifirla") {
                        BodyCounter.shared.reset()
                        print(">>> Counters reset")
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private var resultsCard: some View {
        VStack(spacing: 12) {
            // Body call comparison
            HStack(spacing: 16) {
                VStack {
                    Text("\(BodyCounter.shared.anyViewTotalRebuilds)")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                    Text("body calls")
                        .font(.caption2)
                    Text("AnyView+.id()")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Text("vs")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)

                VStack {
                    Text("\(BodyCounter.shared.concreteTotalRebuilds)")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("body calls")
                        .font(.caption2)
                    Text("Concrete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Per-level breakdown
            if !BodyCounter.shared.anyViewCounts.isEmpty || !BodyCounter.shared.concreteCounts.isEmpty {
                Divider()

                VStack(spacing: 2) {
                    HStack {
                        Text("Level")
                            .frame(width: 50, alignment: .leading)
                        Text("AnyView")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.red)
                        Text("Concrete")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.green)
                    }
                    .font(.caption2.bold())

                    ForEach(0..<depth, id: \.self) { d in
                        HStack {
                            Text("L\(d)\(d == depth - 1 ? " *" : "")")
                                .frame(width: 50, alignment: .leading)
                            Text("\(BodyCounter.shared.anyViewCounts[d] ?? 0)x")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.red)
                            Text("\(BodyCounter.shared.concreteCounts[d] ?? 0)x")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.green)
                        }
                        .font(.caption.monospaced())
                    }

                    Text("* = state degisen view")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Verdict
            if BodyCounter.shared.anyViewTotalRebuilds > 0 {
                Divider()
                let ratio = BodyCounter.shared.concreteTotalRebuilds > 0
                    ? Double(BodyCounter.shared.anyViewTotalRebuilds) / Double(BodyCounter.shared.concreteTotalRebuilds)
                    : Double(BodyCounter.shared.anyViewTotalRebuilds)

                Text("AnyView+.id() \(String(format: "%.0f", ratio))x daha fazla body cagirdi!")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - AnyView Stack (simulates old EasyNavigation pattern)

/// OLD PATTERN: AnyView wrapping + .id(UUID()) on each view.
/// Every render pass, .id(UUID()) produces a new identity → SwiftUI DESTROYS all views.
private struct AnyViewStack: View {
    let maxDepth: Int
    let triggerCount: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<maxDepth, id: \.self) { depth in
                // --- THE BAD PATTERN ---
                // 1. AnyView: type erasure → SwiftUI can't diff properties
                // 2. .id(UUID()): new identity every render → FORCED DESTRUCTION
                AnyView(
                    LevelView(
                        depth: depth,
                        // KEY: Only deepest view gets triggerCount.
                        // Others get a CONSTANT so their props don't change.
                        displayValue: depth == maxDepth - 1 ? triggerCount : -1,
                        color: .red,
                        mode: .anyView
                    )
                )
                .id(UUID()) // ← KILLER: new UUID every time parent body runs
            }
        }
    }
}

// MARK: - Concrete Stack (the correct pattern)

/// NEW PATTERN: Concrete type, no .id(), SwiftUI can diff and skip unchanged views.
private struct ConcreteStack: View {
    let maxDepth: Int
    let triggerCount: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<maxDepth, id: \.self) { depth in
                // --- THE GOOD PATTERN ---
                // Concrete type + no .id() = SwiftUI knows:
                //   "This is the same LevelView at position `depth`"
                //   "Its properties haven't changed" (for non-deepest)
                //   → SKIP body evaluation entirely
                LevelView(
                    depth: depth,
                    displayValue: depth == maxDepth - 1 ? triggerCount : -1,
                    color: .green,
                    mode: .concrete
                )
                // No .id(UUID()) — stable structural identity
            }
        }
    }
}

// MARK: - Shared Level View

private enum BenchmarkMode {
    case anyView, concrete
}

/// A single level view that logs when its body is called.
/// Both AnyView and Concrete stacks use the SAME view type —
/// the only difference is how the PARENT wraps it.
private struct LevelView: View {
    let depth: Int
    let displayValue: Int // -1 = static (no state dependency)
    let color: Color
    let mode: BenchmarkMode

    var body: some View {
        // LOG: This is the proof. Every time this runs, SwiftUI re-evaluated this view's body.
        let _ = {
            let label = mode == .anyView ? "AnyView " : "Concrete"
            let isDeepest = displayValue != -1
            let marker = isDeepest ? " ← STATE DEGISTI" : " (degismedi, gereksiz!)"

            switch mode {
            case .anyView:
                BodyCounter.shared.recordAnyView(depth: depth)
                BodyCounter.shared.endAnyViewTiming()
            case .concrete:
                BodyCounter.shared.recordConcrete(depth: depth)
                BodyCounter.shared.endConcreteTiming()
            }

            print("  [\(label)] body CALLED → depth=\(depth)\(marker)")
        }()

        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.4))
                .frame(width: 6, height: 6)
            Text("L\(depth)")
                .font(.system(size: 10, design: .monospaced))
            Spacer()
            if displayValue != -1 {
                Text("v:\(displayValue)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(displayValue != -1 ? 0.15 : 0.04))
        )
    }
}

// MARK: - Proof 2: .id(UUID()) Destruction

/// Standalone proof that `.id(UUID())` destroys and recreates views on EVERY render.
/// Watch console: WITH .id() triggers onAppear+onDisappear. WITHOUT only triggers body.
public struct IdDestructionProof: View {
    @State private var counter = 0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(".id(UUID()) View Destruction Proof")
                    .font(.headline)

                Text("Counter: \(counter)")
                    .font(.system(.title, design: .monospaced))

                // WITH .id(UUID())
                GroupBox {
                    VStack(spacing: 4) {
                        Text("WITH .id(UUID())")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                        Text("Her render'da onDisappear → onAppear tetiklenir")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        LifecycleView(label: "WITH-ID", counter: counter)
                            .id(UUID()) // ← Forces destruction
                    }
                }

                // WITHOUT .id()
                GroupBox {
                    VStack(spacing: 4) {
                        Text("WITHOUT .id()")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                        Text("Sadece body cagirilir, view KORUNUR")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        LifecycleView(label: "NO-ID", counter: counter)
                        // No .id() — view preserved
                    }
                }

                // WITH AnyView (no .id)
                GroupBox {
                    VStack(spacing: 4) {
                        Text("WITH AnyView (no .id)")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text("Body cagirilir ama view korunur (.id olmadan)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        AnyView(LifecycleView(label: "ANYVIEW", counter: counter))
                        // AnyView without .id — still calls body but doesn't destroy
                    }
                }

                // WITH AnyView + .id(UUID()) — WORST CASE
                GroupBox {
                    VStack(spacing: 4) {
                        Text("WITH AnyView + .id(UUID())")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                        Text("EN KOTU: type erasure + forced destruction")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        AnyView(LifecycleView(label: "ANY+ID", counter: counter))
                            .id(UUID()) // ← Double whammy
                    }
                }

                Button("Counter + 1") {
                    print("\n" + String(repeating: "=", count: 70))
                    print("  .id() PROOF: Counter \(counter) → \(counter + 1)")
                    print("  Beklenen:")
                    print("    WITH-ID  : onDisappear → body → onAppear (VIEW YOK EDILDI)")
                    print("    NO-ID    : body (view korundu)")
                    print("    ANYVIEW  : body (view korundu, ama tip bilgisi yok)")
                    print("    ANY+ID   : onDisappear → body → onAppear (EN KOTU)")
                    print(String(repeating: "-", count: 70))
                    counter += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding()
        }
    }
}

/// View that logs its FULL lifecycle — init, body, onAppear, onDisappear
private struct LifecycleView: View {
    let label: String
    let counter: Int

    @State private var appearCount = 0

    init(label: String, counter: Int) {
        self.label = label
        self.counter = counter
        // Can't print here reliably for struct init, but body tells the story
    }

    var body: some View {
        let _ = print("  [\(label)] body called (counter=\(counter), appearCount=\(appearCount))")

        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.monospaced().bold())
                Spacer()
                Text("counter=\(counter)")
                    .font(.caption.monospaced())
                Text("appears=\(appearCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            appearCount += 1
            print("  [\(label)] onAppear (#\(appearCount)) — VIEW CREATED/REINSERTED")
        }
        .onDisappear {
            print("  [\(label)] onDisappear — VIEW DESTROYED!")
        }
    }
}

// MARK: - Proof 3: AnyView vs Concrete Diffing

/// Shows that AnyView prevents SwiftUI from skipping unchanged views,
/// even WITHOUT .id(). Pure AnyView type-erasure effect.
public struct AnyViewVsConcreteProof: View {
    @State private var counter = 0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("AnyView Type Erasure Proof")
                    .font(.headline)
                Text("3 view var. Sadece 3.'sunun state'i degisiyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Concrete: SwiftUI should skip unchanged views
                GroupBox {
                    VStack(spacing: 4) {
                        Text("Concrete Views")
                            .font(.caption.bold())
                            .foregroundStyle(.green)

                        DiffTestView(label: "Concrete-1", value: "sabit", mode: .concrete)
                        DiffTestView(label: "Concrete-2", value: "sabit", mode: .concrete)
                        DiffTestView(label: "Concrete-3", value: "degisen: \(counter)", mode: .concrete)
                    }
                }

                // AnyView: SwiftUI can't skip because type info is erased
                GroupBox {
                    VStack(spacing: 4) {
                        Text("AnyView-Wrapped Views")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)

                        AnyView(DiffTestView(label: "AnyView-1", value: "sabit", mode: .anyViewWrapped))
                        AnyView(DiffTestView(label: "AnyView-2", value: "sabit", mode: .anyViewWrapped))
                        AnyView(DiffTestView(label: "AnyView-3", value: "degisen: \(counter)", mode: .anyViewWrapped))
                    }
                }

                Button("Counter + 1 (sadece 3. view degismeli)") {
                    print("\n" + String(repeating: "=", count: 70))
                    print("  ANYVIEW vs CONCRETE: Counter \(counter) → \(counter + 1)")
                    print("  Beklenen:")
                    print("    Concrete-1: body CAGRILMAMALI (prop degismedi)")
                    print("    Concrete-2: body CAGRILMAMALI (prop degismedi)")
                    print("    Concrete-3: body CAGRILMALI (prop degisti)")
                    print("    AnyView-*:  body hepsi cagrilabilir (type erasure)")
                    print(String(repeating: "-", count: 70))
                    counter += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding()
        }
    }
}

private enum DiffMode {
    case concrete, anyViewWrapped
}

private struct DiffTestView: View {
    let label: String
    let value: String
    let mode: DiffMode

    var body: some View {
        let _ = {
            let emoji = mode == .concrete ? "🟢" : "🟠"
            print("  \(emoji) [\(label)] body called (value=\"\(value)\")")
        }()

        HStack {
            Text(label)
                .font(.caption.monospaced())
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(mode == .concrete ? .green : .orange)
        }
        .padding(6)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
