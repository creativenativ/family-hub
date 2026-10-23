import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import Vision

struct CookbookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var searchText = ""
    @State private var remoteResults: [RemoteRecipeSummary] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selectedRemote: RemoteRecipeSummary?
    @State private var showingManualAdd = false
    @State private var recipeToView: Recipe?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Search web recipes…", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { Task { await runSearch() } }

                    Button {
                        Task { await runSearch() }
                    } label: {
                        if isSearching {
                            ProgressView()
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).count < 2 || isSearching)
                }

                if let searchError {
                    Text(searchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Find Recipes")
            } footer: {
                Text("Searches recipe names, ingredients, categories (e.g. Pasta), and cuisines (e.g. Italian). Results include a short description when available.")
            }

            if !remoteResults.isEmpty {
                Section {
                    ForEach(remoteResults) { result in
                        Button {
                            selectedRemote = result
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                remoteThumbnail(result.thumbnailURL)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)

                                    HStack(spacing: 6) {
                                        if let category = result.category {
                                            Text(category)
                                        }
                                        if let area = result.area {
                                            Text("· \(area)")
                                        }
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)

                                    if let description = result.description, !description.isEmpty {
                                        Text(description)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 0)
                                if recipes.contains(where: { $0.externalID == result.id }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.themeAccent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Web Results (\(remoteResults.count))")
                }
            }

            Section {
                if recipes.isEmpty {
                    Text("No saved recipes yet. Search above or add one manually.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipes, id: \.id) { recipe in
                        Button {
                            recipeToView = recipe
                        } label: {
                            HStack(spacing: 12) {
                                RecipeThumbnail(recipe: recipe)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(recipe.ingredients.count) ingredients · \(recipe.servings) servings")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRecipes)
                }
            } header: {
                Text("Saved Cookbook (\(recipes.count))")
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingManualAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $selectedRemote) { summary in
            RemoteRecipeDetailSheet(summary: summary) { saved in
                if !recipes.contains(where: { $0.externalID == saved.externalID && !saved.externalID.isEmpty }) {
                    modelContext.insert(saved)
                }
                selectedRemote = nil
            }
        }
        .sheet(isPresented: $showingManualAdd) {
            ManualRecipeEditorView()
        }
        .sheet(item: $recipeToView) { recipe in
            SavedRecipeDetailView(recipe: recipe)
        }
    }

    private func runSearch() async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            remoteResults = try await RecipeSearchService.search(query: searchText)
        } catch {
            remoteResults = []
            searchError = error.localizedDescription
        }
    }

    private func deleteRecipes(at offsets: IndexSet) {
        for index in offsets {
            let recipe = recipes[index]
            FamilySyncService.shared.noteLocalDeletion(prefix: "recipe", id: recipe.id)
            modelContext.delete(recipe)
        }
    }

    @ViewBuilder
    private func remoteThumbnail(_ urlString: String?) -> some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct RecipeThumbnail: View {
    let recipe: Recipe

    var body: some View {
        Group {
            if let image = recipe.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !recipe.imageURL.isEmpty, let url = URL(string: recipe.imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        Color(.tertiarySystemFill)
            .overlay {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.secondary)
            }
    }
}

struct RemoteRecipeDetailSheet: View {
    let summary: RemoteRecipeSummary
    let onSave: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: RemoteRecipeDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading recipe…")
                } else if let detail {
                    recipeContent(detail)
                } else {
                    ContentUnavailableView(
                        "Couldn't Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? "Try again.")
                    )
                }
            }
            .navigationTitle(summary.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save to Cookbook") {
                        guard let detail else { return }
                        let recipe = Recipe(
                            name: detail.name,
                            summary: [detail.category, detail.area].compactMap { $0 }.joined(separator: " · "),
                            instructions: detail.instructions,
                            sourceURL: detail.sourceURL ?? detail.youtubeURL ?? "",
                            imageURL: detail.thumbnailURL ?? "",
                            servings: 4,
                            externalID: detail.id,
                            ingredients: detail.ingredients
                        )
                        onSave(recipe)
                        dismiss()
                    }
                    .disabled(detail == nil)
                }
            }
            .task { await loadDetail() }
        }
    }

    private func recipeContent(_ detail: RemoteRecipeDetail) -> some View {
        List {
            if let thumb = detail.thumbnailURL, let url = URL(string: thumb) {
                Section {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color(.tertiarySystemFill)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .listRowInsets(EdgeInsets())
                }
            }

            Section("Ingredients") {
                ForEach(detail.ingredients) { ingredient in
                    Text(ingredient.displayLine)
                }
            }

            if !detail.instructions.isEmpty {
                Section("Instructions") {
                    Text(detail.instructions)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await RecipeSearchService.detail(id: summary.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SavedRecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let local = recipe.displayImage {
                    Section {
                        Image(uiImage: local)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipped()
                            .listRowInsets(EdgeInsets())
                    }
                } else if !recipe.imageURL.isEmpty, let url = URL(string: recipe.imageURL) {
                    Section {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color(.tertiarySystemFill)
                            }
                        }
                        .frame(height: 180)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section("Ingredients") {
                    ForEach(recipe.ingredients) { ingredient in
                        Text(ingredient.displayLine)
                    }
                }

                if !recipe.instructions.isEmpty {
                    Section("Instructions") {
                        Text(recipe.instructions)
                            .font(.subheadline)
                    }
                }

                if !recipe.sourceURL.isEmpty, let url = URL(string: recipe.sourceURL) {
                    Section {
                        Link("Open source", destination: url)
                    }
                }
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ManualRecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var servings = 4
    @State private var instructions = ""
    @State private var ingredientLines = ""
    @State private var recipeImage: UIImage?
    @State private var usePhotoAsRecipeImage = false

    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var scannedImage: UIImage?
    @State private var isRecognizing = false
    @State private var ocrError: String?
    @State private var showingPhotoPrompt = false
    @State private var pendingOCR: RecipeOCRResult?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingSourcePicker = true
                    } label: {
                        Label(
                            isRecognizing ? "Reading text…" : "Scan recipe photo",
                            systemImage: "text.viewfinder"
                        )
                    }
                    .disabled(isRecognizing)

                    if isRecognizing {
                        ProgressView("Copying words from photo…")
                    }

                    if let ocrError {
                        Text(ocrError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("From Photo")
                } footer: {
                    Text("Take or choose a photo of a recipe card, cookbook page, or screenshot. Words are copied into the fields below.")
                }

                if let recipeImage, usePhotoAsRecipeImage {
                    Section("Recipe Photo") {
                        Image(uiImage: recipeImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                        Button("Remove photo", role: .destructive) {
                            self.recipeImage = nil
                            usePhotoAsRecipeImage = false
                        }
                    }
                }

                Section("Recipe") {
                    TextField("Name", text: $name)
                    Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                }

                Section {
                    TextField("One ingredient per line\ne.g. 2 cups flour", text: $ingredientLines, axis: .vertical)
                        .lineLimit(6...12)
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Tip: put quantity first, then the ingredient name.")
                }

                Section("Instructions") {
                    TextField("Steps…", text: $instructions, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isRecognizing)
                }
            }
            .confirmationDialog("Scan Recipe Photo", isPresented: $showingSourcePicker) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showingCamera = true }
                }
                Button("Choose from Library") { showingLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $scannedImage)
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: scannedImage) { _, image in
                guard let image else { return }
                Task { await processScannedImage(image) }
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task { await loadLibraryImage(item) }
            }
            .alert("Use Photo for Recipe?", isPresented: $showingPhotoPrompt) {
                Button("Yes, use as recipe photo") {
                    applyOCR(usePhoto: true)
                }
                Button("No, text only") {
                    applyOCR(usePhoto: false)
                }
                Button("Cancel", role: .cancel) {
                    pendingOCR = nil
                    scannedImage = nil
                    libraryItem = nil
                }
            } message: {
                Text("Text was copied from the photo. Would you also like to save this picture as the recipe photo?")
            }
        }
    }

    private func loadLibraryImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { ocrError = "Couldn't open that photo." }
                return
            }
            await processScannedImage(image)
        } catch {
            await MainActor.run { ocrError = "Couldn't open that photo." }
        }
    }

    private func processScannedImage(_ image: UIImage) async {
        await MainActor.run {
            isRecognizing = true
            ocrError = nil
        }

        do {
            let result = try await RecipeOCRService.recognizeText(in: image)
            await MainActor.run {
                isRecognizing = false
                pendingOCR = result
                scannedImage = image
                showingPhotoPrompt = true
            }
        } catch {
            await MainActor.run {
                isRecognizing = false
                ocrError = error.localizedDescription
                // Still offer to use photo even if OCR fails
                pendingOCR = RecipeOCRResult(
                    fullText: "",
                    suggestedName: "",
                    suggestedIngredients: "",
                    suggestedInstructions: ""
                )
                scannedImage = image
                showingPhotoPrompt = true
            }
        }
    }

    private func applyOCR(usePhoto: Bool) {
        if let pendingOCR {
            if name.trimmingCharacters(in: .whitespaces).isEmpty, !pendingOCR.suggestedName.isEmpty {
                name = pendingOCR.suggestedName
            }
            if !pendingOCR.suggestedIngredients.isEmpty {
                if ingredientLines.isEmpty {
                    ingredientLines = pendingOCR.suggestedIngredients
                } else {
                    ingredientLines += "\n" + pendingOCR.suggestedIngredients
                }
            }
            if !pendingOCR.suggestedInstructions.isEmpty {
                if instructions.isEmpty {
                    instructions = pendingOCR.suggestedInstructions
                } else {
                    instructions += "\n" + pendingOCR.suggestedInstructions
                }
            }
            // If OCR found text but couldn't split, dump into instructions when fields empty
            if pendingOCR.suggestedIngredients.isEmpty,
               pendingOCR.suggestedInstructions.isEmpty,
               !pendingOCR.fullText.isEmpty,
               instructions.isEmpty {
                instructions = pendingOCR.fullText
            }
        }

        usePhotoAsRecipeImage = usePhoto
        if usePhoto {
            recipeImage = scannedImage
        }

        pendingOCR = nil
        scannedImage = nil
        libraryItem = nil
    }

    private func save() {
        let cleaned = ingredientLines
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(parseIngredientLine)

        let compressed = usePhotoAsRecipeImage
            ? recipeImage?.jpegData(compressionQuality: 0.75)
            : nil

        let recipe = Recipe(
            name: name.trimmingCharacters(in: .whitespaces),
            instructions: instructions,
            imageData: compressed,
            servings: servings,
            ingredients: cleaned
        )
        modelContext.insert(recipe)
        dismiss()
    }

    private func parseIngredientLine(_ line: String) -> RecipeIngredient {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else {
            return RecipeIngredient(name: line, quantity: "")
        }

        let startsWithNumber = first.first?.isNumber == true || first.contains("/")
        if startsWithNumber, parts.count >= 3 {
            return RecipeIngredient(
                name: parts.dropFirst(2).joined(separator: " "),
                quantity: "\(parts[0]) \(parts[1])"
            )
        }
        if startsWithNumber, parts.count >= 2 {
            return RecipeIngredient(
                name: parts.dropFirst().joined(separator: " "),
                quantity: parts[0]
            )
        }
        return RecipeIngredient(name: line, quantity: "")
    }
}
// MARK: - Recipe photo OCR (kept in this file so Xcode always compiles it with the editor)

struct RecipeOCRResult {
    let fullText: String
    let suggestedName: String
    let suggestedIngredients: String
    let suggestedInstructions: String
}

enum RecipeOCRService {
    enum OCRError: LocalizedError {
        case invalidImage
        case noTextFound
        case recognitionFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage: "Couldn't read that photo."
            case .noTextFound: "No text was found in the photo. Try a clearer picture of the recipe."
            case .recognitionFailed: "Text recognition failed. Please try again."
            }
        }
    }

    static func recognizeText(in image: UIImage) async throws -> RecipeOCRResult {
        guard let cgImage = image.cgImage ?? image.fh_normalizedCGImage() else {
            throw OCRError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { throw OCRError.noTextFound }

        return parseRecipe(from: lines)
    }

    private static func parseRecipe(from lines: [String]) -> RecipeOCRResult {
        let fullText = lines.joined(separator: "\n")
        let lowerLines = lines.map { $0.lowercased() }

        let ingredientHeaderIndex = lowerLines.firstIndex(where: {
            $0 == "ingredients" || $0.hasPrefix("ingredients") || $0.contains("ingredient list")
        })
        let instructionHeaderIndex = lowerLines.firstIndex(where: {
            $0 == "instructions" || $0 == "directions" || $0 == "method" || $0 == "steps"
                || $0.hasPrefix("instructions") || $0.hasPrefix("directions") || $0.hasPrefix("method")
        })

        var name = ""
        var ingredientLines: [String] = []
        var instructionLines: [String] = []

        if let first = lines.first, first.count <= 60, !looksLikeIngredient(first) {
            name = first
        }

        if let ingredientHeaderIndex, let instructionHeaderIndex, ingredientHeaderIndex < instructionHeaderIndex {
            ingredientLines = Array(lines[(ingredientHeaderIndex + 1)..<instructionHeaderIndex])
            instructionLines = Array(lines[(instructionHeaderIndex + 1)...])
        } else if let ingredientHeaderIndex {
            let after = Array(lines[(ingredientHeaderIndex + 1)...])
            let split = after.split(whereSeparator: { looksLikeInstructionHeader($0) })
            ingredientLines = Array(split.first ?? [])
            if split.count > 1 {
                instructionLines = split.dropFirst().flatMap { Array($0) }
            }
        } else if let instructionHeaderIndex {
            if instructionHeaderIndex > 0 {
                let before = Array(lines[0..<instructionHeaderIndex])
                ingredientLines = before.filter { looksLikeIngredient($0) && $0 != name }
            }
            instructionLines = Array(lines[(instructionHeaderIndex + 1)...])
        } else {
            for (index, line) in lines.enumerated() {
                if index == 0 && line == name { continue }
                if looksLikeIngredient(line) {
                    ingredientLines.append(line)
                } else if line.count > 40 || looksLikeInstruction(line) {
                    instructionLines.append(line)
                } else if ingredientLines.isEmpty && name.isEmpty {
                    name = line
                } else {
                    ingredientLines.append(line)
                }
            }
        }

        ingredientLines = ingredientLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isSectionHeader($0) }
        instructionLines = instructionLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isSectionHeader($0) }

        return RecipeOCRResult(
            fullText: fullText,
            suggestedName: name,
            suggestedIngredients: ingredientLines.joined(separator: "\n"),
            suggestedInstructions: instructionLines.joined(separator: "\n")
        )
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        let lower = line.lowercased()
        return ["ingredients", "instructions", "directions", "method", "steps"].contains {
            lower == $0 || lower.hasPrefix($0 + ":")
        }
    }

    private static func looksLikeInstructionHeader(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower == "instructions" || lower == "directions" || lower == "method" || lower == "steps"
            || lower.hasPrefix("instructions") || lower.hasPrefix("directions")
    }

    private static func looksLikeIngredient(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("-") || lower.hasPrefix("•") || lower.hasPrefix("*") { return true }
        if line.first?.isNumber == true { return true }
        let units = ["cup", "tbsp", "tsp", "oz", "lb", "g ", "kg", "ml", "clove", "pinch", "can", "package"]
        return units.contains(where: { lower.contains($0) })
    }

    private static func looksLikeInstruction(_ line: String) -> Bool {
        let lower = line.lowercased()
        let verbs = ["preheat", "mix", "stir", "bake", "cook", "heat", "add", "combine", "whisk", "serve", "pour", "place", "remove"]
        return verbs.contains(where: { lower.contains($0) })
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
    }
}

private extension UIImage {
    func fh_normalizedCGImage() -> CGImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
