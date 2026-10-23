import PhotosUI
import SwiftUI
import SwiftData
import UIKit

struct MemberEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var member: FamilyMember?

    @State private var name = ""
    @State private var selectedColorHex = MemberColor.blue.hex
    @State private var profileImageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var inviteEmail = ""
    @State private var invitePhone = ""

    private var isEditing: Bool { member != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        profilePhotoPicker
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Tribe member name", text: $name)
                }

                Section {
                    TextField("Email", text: $inviteEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $invitePhone)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Invite contact")
                } footer: {
                    Text("Used to send Tribe Time calendar invites by text or email.")
                }

                Section {
                    ColorWheelPicker(hex: $selectedColorHex)
                        .padding(.vertical, 4)
                } header: {
                    Text("Calendar Color")
                } footer: {
                    Text("Drag the wheel for hue and saturation, then use the brightness slider. Events and chores assigned to this person use this color on the calendar.")
                }
            }
            .navigationTitle(isEditing ? "Edit Tribe Member" : "Add Tribe Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadExistingMember)
            .onChange(of: selectedPhoto) { _, newItem in
                loadPhoto(from: newItem)
            }
        }
    }

    private var profilePhotoPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                avatarPreview
                    .frame(width: 96, height: 96)

                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let profileImageData, let image = UIImage(data: profileImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(previewColor, lineWidth: 3)
                }
        } else {
            Circle()
                .fill(previewColor)
                .overlay {
                    Text(name.isEmpty ? "?" : name.prefix(1).uppercased())
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    private var previewColor: Color {
        Color(hex: selectedColorHex) ?? .blue
    }

    private func loadExistingMember() {
        guard let member else { return }
        name = member.name
        selectedColorHex = member.colorHex
        profileImageData = member.profileImageData
        inviteEmail = member.inviteEmail
        invitePhone = member.invitePhone
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let compressed = image.jpegData(compressionQuality: 0.75) else { return }
            await MainActor.run {
                profileImageData = compressed
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let member {
            member.name = trimmedName
            member.colorHex = selectedColorHex
            member.profileImageData = profileImageData
            member.inviteEmail = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            member.invitePhone = invitePhone.trimmingCharacters(in: .whitespacesAndNewlines)
            member.touchForSync()
        } else {
            let newMember = FamilyMember(
                name: trimmedName,
                colorHex: selectedColorHex,
                profileImageData: profileImageData
            )
            newMember.inviteEmail = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            newMember.invitePhone = invitePhone.trimmingCharacters(in: .whitespacesAndNewlines)
            modelContext.insert(newMember)
        }
        dismiss()
    }
}

#Preview {
    MemberEditorView()
}
