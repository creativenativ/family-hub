import SwiftUI
import SwiftData

/// Diagonal glass panel that opens from the top-left of the screen.
struct NotificationsPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<PendingEmailImport> { $0.statusRaw == "pending" },
        sort: \PendingEmailImport.createdAt,
        order: .reverse
    ) private var pendingImports: [PendingEmailImport]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]

    @Binding var isPresented: Bool
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dim scrim — tap outside to close
            Color.black.opacity(isPresented ? 0.28 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        isPresented = false
                    }
                }
                .allowsHitTesting(isPresented)

            if isPresented {
                panelContent
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: DiagonalRevealModifier(progress: 0),
                                identity: DiagonalRevealModifier(progress: 1)
                            ),
                            removal: .opacity.combined(with: .scale(scale: 0.85, anchor: .topLeading))
                        )
                    )
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isPresented)
    }

    private var panelContent: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()
                    .opacity(0.35)

                if pendingImports.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(pendingImports, id: \.id) { item in
                                PendingImportCard(
                                    item: item,
                                    members: members,
                                    onApprove: { approve(item) },
                                    onDecline: { decline(item) }
                                )
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .frame(width: min(400, geo.size.width - 24), alignment: .topLeading)
            .frame(maxHeight: geo.size.height * 0.78, alignment: .top)
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    LinearGradient(
                        colors: [
                            Color.themeAccent.opacity(0.18),
                            Color.white.opacity(0.08),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(DiagonalPanelShape())
            .overlay {
                DiagonalPanelShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.12),
                                Color.themeAccent.opacity(0.35),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.22), radius: 24, x: 6, y: 14)
            .sheet(isPresented: $showingSettings) {
                NotificationSettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.title2)
                .foregroundStyle(Color.themeAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.title3.weight(.semibold))
                Text(pendingImports.isEmpty ? "All clear" : "\(pendingImports.count) awaiting approval")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notification settings")

            if !pendingImports.isEmpty {
                Button("Decline All", role: .destructive) {
                    declineAll()
                }
                .font(.subheadline.weight(.semibold))
            }

            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No approvals waiting")
                .font(.title3.weight(.semibold))
            Text("Email imports land here for approval before the calendar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button {
                showingSettings = true
            } label: {
                Label("Notification settings", systemImage: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
    }

    private func approve(_ item: PendingEmailImport) {
        let event = CalendarEvent(
            title: item.title,
            startDate: item.startDate,
            endDate: item.endDate,
            isAllDay: item.isAllDay,
            notes: noteForApproved(item),
            location: item.location,
            assignedMember: item.suggestedMember
        )
        modelContext.insert(event)
        item.status = .approved
        modelContext.delete(item)
    }

    private func decline(_ item: PendingEmailImport) {
        item.status = .declined
        modelContext.delete(item)
    }

    private func declineAll() {
        for item in pendingImports {
            modelContext.delete(item)
        }
    }

    private func noteForApproved(_ item: PendingEmailImport) -> String {
        var parts = ["Approved from email · \(item.category.label)"]
        if !item.notes.isEmpty {
            parts.append(item.notes)
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Top-left launcher

struct NotificationsLaunchButton: View {
    let pendingCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                if pendingCount > 0 {
                    ThemeBadge(count: pendingCount, maximum: 9)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
        .accessibilityValue(pendingCount == 0 ? "None pending" : "\(pendingCount) pending")
    }
}

// MARK: - Diagonal geometry

/// Panel clipped with a diagonal cut on the bottom-trailing edge.
struct DiagonalPanelShape: Shape {
    var cutRatio: CGFloat = 0.12

    func path(in rect: CGRect) -> Path {
        let cut = min(rect.width, rect.height) * cutRatio
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 18))
        path.closeSubpath()
        return path
    }
}

struct DiagonalRevealModifier: ViewModifier {
    var progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.72 + (0.28 * progress), anchor: .topLeading)
            .rotationEffect(.degrees(-8 + (8 * Double(progress))), anchor: .topLeading)
            .offset(x: (1 - progress) * -40, y: (1 - progress) * -28)
    }
}

struct PendingImportCard: View {
    @Bindable var item: PendingEmailImport
    let members: [FamilyMember]
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.category.icon)
                    .font(.title3)
                    .foregroundStyle(Color.themeAccent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        Text(item.category.label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.themeAccent.opacity(0.18))
                            .clipShape(Capsule())

                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if item.isAllDay {
                        Label(
                            item.startDate.formatted(date: .abbreviated, time: .omitted) + " · All day",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            "\(item.startDate.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !item.location.isEmpty {
                        Label(item.location, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            if !members.isEmpty {
                Picker("Assign to", selection: $item.suggestedMember) {
                    Text("Everyone").tag(nil as FamilyMember?)
                    ForEach(members, id: \.id) { member in
                        Text(member.name).tag(member as FamilyMember?)
                    }
                }
                .pickerStyle(.menu)
            }

            if !item.sourceSnippet.isEmpty {
                Text(item.sourceSnippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 10) {
                Button(role: .destructive, action: onDecline) {
                    Label("Decline", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ZStack {
        Color.blue.opacity(0.3).ignoresSafeArea()
        NotificationsPanel(isPresented: .constant(true))
    }
    .modelContainer(for: [PendingEmailImport.self, FamilyMember.self, CalendarEvent.self], inMemory: true)
}
