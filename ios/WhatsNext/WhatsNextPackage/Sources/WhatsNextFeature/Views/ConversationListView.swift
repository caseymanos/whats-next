import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ConversationListViewModel()
    @State private var showingProfile = false
    @State private var showingNewConversation = false
    @State private var showingCreateGroup = false
    @State private var navPath = NavigationPath()
    @State private var hasAppeared = false // Track if view has appeared before
    
    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    ProgressView()
                } else if viewModel.conversations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No conversations yet")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Just tap to start a conversation")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingNewConversation = true
                    }
                } else {
                    List {
                        ForEach(viewModel.conversations) { conversation in
                            NavigationLink {
                                if let userId = authViewModel.currentUser?.id {
                                    ChatView(conversation: conversation, currentUserId: userId)
                                }
                            } label: {
                                ConversationRow(
                                    conversation: conversation,
                                    currentUserId: authViewModel.currentUser?.id ?? UUID()
                                )
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                guard let userId = authViewModel.currentUser?.id else { return }
                                await viewModel.deleteConversations(at: indexSet, currentUserId: userId)
                            }
                        }
                    }
                    .refreshable {
                        if let userId = authViewModel.currentUser?.id {
                            await viewModel.fetchConversations(userId: userId)
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .inAppBanner { conversationId in
                // Handle banner tap - navigate to the conversation
                if let conversation = viewModel.conversations.first(where: { $0.id == conversationId }) {
                    navPath.append(conversation)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingNewConversation = true
                        } label: {
                            Label("New Direct Message", systemImage: "person.fill")
                        }
                        
                        Button {
                            showingCreateGroup = true
                        } label: {
                            Label("New Group", systemImage: "person.3.fill")
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewConversation) {
                if let userId = authViewModel.currentUser?.id {
                    NewConversationView(currentUserId: userId) { conversation in
                        viewModel.conversations.insert(conversation, at: 0)
                        showingNewConversation = false
                        DispatchQueue.main.async {
                            navPath.append(conversation)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                if let userId = authViewModel.currentUser?.id {
                    CreateGroupView(currentUserId: userId) { conversation in
                        // Add the new group to the list
                        viewModel.conversations.insert(conversation, at: 0)
                    }
                }
            }
            .task {
                // Only fetch on first appearance to prevent flash when switching tabs
                guard !hasAppeared else { return }
                hasAppeared = true

                if let userId = authViewModel.currentUser?.id {
                    await viewModel.fetchConversations(userId: userId)
                }
            }
            .navigationDestination(for: Conversation.self) { conv in
                if let userId = authViewModel.currentUser?.id {
                    ChatView(conversation: conv, currentUserId: userId)
                }
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let currentUserId: UUID

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with profile picture or initials
            AvatarView(
                avatarUrl: avatarUrl,
                displayName: displayName,
                size: .medium
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.headline)

                    Spacer()

                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage.createdAt, formatter: timeFormatter)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastMessage = conversation.lastMessage {
                    Text(previewText(lastMessage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        if conversation.isGroup {
            return conversation.name ?? "Group Chat"
        } else {
            // For 1:1, show other user's name
            if let otherUser = conversation.participants?.first(where: { $0.id != currentUserId }) {
                return otherUser.displayName ?? otherUser.username ?? otherUser.email ?? "Unknown User"
            }
            return "Direct Message"
        }
    }

    private var avatarUrl: String? {
        if conversation.isGroup {
            return conversation.avatarUrl
        } else {
            return conversation.participants?.first(where: { $0.id != currentUserId })?.avatarUrl
        }
    }

    private func previewText(_ message: Message) -> String {
        if conversation.isGroup, let sender = message.sender?.displayName ?? message.sender?.username {
            return "\(sender): \(message.content ?? "Media")"
        }
        return message.content ?? "Media"
    }
}

private let timeFormatter: DateFormatter = {
    let df = DateFormatter()
    df.timeStyle = .short
    df.dateStyle = .none
    return df
}()

struct NewConversationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = NewConversationViewModel()
    
    let currentUserId: UUID
    let onConversationCreated: (Conversation) -> Void
    
    @State private var searchText = ""
    @State private var selectedUser: User?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search users", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, newValue in
                            Task { await viewModel.searchUsers(currentUserId: currentUserId, search: newValue) }
                        }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                if viewModel.isLoading {
                    ProgressView().frame(maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    ContentUnavailableView("No Users Found", systemImage: "person.2.slash", description: Text("Try adjusting your search"))
                } else {
                    List(viewModel.results) { user in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(user.displayName ?? user.username ?? "Unknown")
                                if let email = user.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if selectedUser?.id == user.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedUser = user }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") { Task { await createDM() } }
                        .disabled(selectedUser == nil || viewModel.isCreating)
                }
            }
            .task { await viewModel.searchUsers(currentUserId: currentUserId, search: "") }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage { Text(error) }
            }
        }
    }
    
    private func createDM() async {
        guard let other = selectedUser else { return }
        if let conv = await viewModel.createDirect(currentUserId: currentUserId, otherUserId: other.id) {
            onConversationCreated(conv)
            dismiss()
        }
    }
}

@MainActor
final class NewConversationViewModel: ObservableObject {
    @Published var results: [User] = []
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var errorMessage: String?
    
    private let supabase = SupabaseClientService.shared
    private let conversationService = ConversationService()
    
    func searchUsers(currentUserId: UUID, search: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            var builder = supabase.database
                .from("users")
                .select()
                .neq("id", value: currentUserId)
            if !term.isEmpty {
                let pattern = "%\(term)%"
                builder = builder.or("display_name.ilike.\(pattern),username.ilike.\(pattern),email.ilike.\(pattern)")
            }
            results = try await builder.limit(50).execute().value
        } catch {
            errorMessage = "Failed to search users"
        }
    }
    
    func createDirect(currentUserId: UUID, otherUserId: UUID) async -> Conversation? {
        isCreating = true
        defer { isCreating = false }
        do {
            return try await conversationService.createDirectConversation(currentUserId: currentUserId, otherUserId: otherUserId)
        } catch {
            errorMessage = "Failed to start conversation"
            return nil
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showImagePicker = false
    @State private var showImageSourcePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            AvatarView(
                                avatarUrl: authViewModel.currentUser?.avatarUrl,
                                displayName: authViewModel.currentUser?.displayName ?? authViewModel.currentUser?.username ?? "U",
                                size: .xlarge
                            )

                            Button {
                                showImageSourcePicker = true
                            } label: {
                                Label("Change Photo", systemImage: "camera.circle.fill")
                            }
                            .buttonStyle(.borderless)

                            if authViewModel.currentUser?.avatarUrl != nil {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteAvatar(userId: authViewModel.currentUser?.id)
                                        await authViewModel.refreshCurrentUser()
                                    }
                                } label: {
                                    Text("Remove Photo")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Profile Picture")
                }

                Section("Account") {
                    if let user = authViewModel.currentUser {
                        LabeledContent("Email", value: user.email ?? "N/A")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("Enter username", text: $viewModel.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.username) { _, newValue in
                                Task {
                                    await viewModel.checkUsernameAvailability(
                                        userId: authViewModel.currentUser?.id
                                    )
                                }
                            }

                        if viewModel.isCheckingUsername {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Checking availability...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if !viewModel.username.isEmpty && viewModel.username != (authViewModel.currentUser?.username ?? "") {
                            if viewModel.isUsernameAvailable {
                                Label("Available", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Label("Already taken", systemImage: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("Enter display name", text: $viewModel.displayName)
                    }
                } header: {
                    Text("Profile Information")
                } footer: {
                    Text("Username must be 3-20 characters and contain only letters, numbers, and underscores.")
                }

                if viewModel.hasChanges(currentUser: authViewModel.currentUser) {
                    Section {
                        Button {
                            Task {
                                await viewModel.saveChanges(
                                    userId: authViewModel.currentUser?.id
                                )
                                if viewModel.saveSuccess {
                                    // Refresh current user
                                    await authViewModel.refreshCurrentUser()
                                }
                            }
                        } label: {
                            if viewModel.isSaving {
                                HStack {
                                    ProgressView()
                                    Text("Saving...")
                                }
                            } else {
                                Text("Save Changes")
                            }
                        }
                        .disabled(!viewModel.canSave)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Developer") {
                    NavigationLink {
                        DebugView()
                    } label: {
                        Label("Debug Settings", systemImage: "hammer.fill")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await authViewModel.signOut()
                            dismiss()
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Sign Out")
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Choose Photo Source", isPresented: $showImageSourcePicker) {
                Button("Camera") {
                    viewModel.imageSourceType = .camera
                    showImagePicker = true
                }
                Button("Photo Library") {
                    viewModel.imageSourceType = .photoLibrary
                    showImagePicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(
                    sourceType: viewModel.imageSourceType,
                    onImagePicked: { image in
                        Task {
                            await viewModel.uploadAvatar(
                                image: image,
                                userId: authViewModel.currentUser?.id
                            )
                            await authViewModel.refreshCurrentUser()
                        }
                    }
                )
            }
            .onAppear {
                viewModel.loadUser(authViewModel.currentUser)
            }
        }
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var displayName: String = ""
    @Published var isCheckingUsername = false
    @Published var isUsernameAvailable = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var saveSuccess = false
    @Published var isUploadingAvatar = false

    var imageSourceType: ImagePickerView.SourceType = .photoLibrary

    private let userService = UserService()
    private let imageUploadService = ImageUploadService()
    private var checkTask: Task<Void, Never>?

    func loadUser(_ user: User?) {
        username = user?.username ?? ""
        displayName = user?.displayName ?? ""
        saveSuccess = false
        errorMessage = nil
    }

    func hasChanges(currentUser: User?) -> Bool {
        let usernameChanged = username != (currentUser?.username ?? "")
        let displayNameChanged = displayName != (currentUser?.displayName ?? "")
        return usernameChanged || displayNameChanged
    }

    var canSave: Bool {
        guard !isSaving && !isCheckingUsername else { return false }

        // Username must be valid if changed
        let usernameValid = username.isEmpty || userService.validateUsername(username)

        // If username changed, must be available
        let usernameOk = username.isEmpty || isUsernameAvailable

        return usernameValid && usernameOk
    }

    func checkUsernameAvailability(userId: UUID?) async {
        // Cancel previous check
        checkTask?.cancel()

        // Don't check if empty or invalid format
        guard !username.isEmpty, userService.validateUsername(username) else {
            isUsernameAvailable = false
            return
        }

        checkTask = Task {
            // Debounce - wait 500ms
            try? await Task.sleep(for: .milliseconds(500))

            guard !Task.isCancelled else { return }

            isCheckingUsername = true
            defer { isCheckingUsername = false }

            do {
                isUsernameAvailable = try await userService.checkUsernameAvailability(
                    username: username,
                    excludeUserId: userId
                )
            } catch {
                isUsernameAvailable = false
            }
        }
    }

    func saveChanges(userId: UUID?) async {
        guard let userId = userId else { return }

        isSaving = true
        errorMessage = nil
        saveSuccess = false
        defer { isSaving = false }

        do {
            // Update username if changed
            if !username.isEmpty {
                try await userService.updateUsername(userId: userId, username: username)
            }

            // Update display name if changed
            try await userService.updateDisplayName(userId: userId, displayName: displayName)

            saveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            saveSuccess = false
        }
    }

    func uploadAvatar(image: UIImage, userId: UUID?) async {
        guard let userId = userId else { return }

        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }

        do {
            let avatarUrl = try await imageUploadService.uploadProfilePicture(userId: userId, image: image)
            try await userService.updateAvatarUrl(userId: userId, avatarUrl: avatarUrl)
        } catch {
            errorMessage = "Failed to upload avatar: \(error.localizedDescription)"
        }
    }

    func deleteAvatar(userId: UUID?) async {
        guard let userId = userId else { return }

        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }

        do {
            try await imageUploadService.deleteProfilePicture(userId: userId)
            try await userService.updateAvatarUrl(userId: userId, avatarUrl: nil)
        } catch {
            errorMessage = "Failed to delete avatar: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ConversationListView()
        .environmentObject(AuthViewModel())
}

