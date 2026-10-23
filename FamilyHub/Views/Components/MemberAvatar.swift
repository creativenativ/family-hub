import SwiftUI

struct MemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 36
    var showColorRing: Bool = true

    var body: some View {
        Group {
            if let image = member.profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(member.color)
                    .overlay {
                        Text(member.initial)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showColorRing {
                Circle()
                    .strokeBorder(member.color, lineWidth: max(2, size * 0.06))
            }
        }
    }
}

struct MemberChip: View {
    let member: FamilyMember
    var isSelected: Bool = false
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            MemberAvatar(member: member, size: size, showColorRing: false)
            Text(member.name)
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? member.color.opacity(0.25) : Color(.secondarySystemBackground))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(isSelected ? member.color : Color.clear, lineWidth: 2)
        }
    }
}

#Preview {
    let member = FamilyMember(name: "Alex", colorHex: MemberColor.purple.hex)
    return HStack {
        MemberAvatar(member: member)
        MemberChip(member: member, isSelected: true)
    }
    .padding()
}
