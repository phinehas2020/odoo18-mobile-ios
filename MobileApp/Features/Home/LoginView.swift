import SwiftUI

struct LoginView: View {
  @EnvironmentObject private var config: EnvironmentConfig
  @EnvironmentObject private var authStore: AuthStore

  @StateObject private var viewModel = LoginViewModel()
  @State private var serverURLText: String = ""
  @State private var showConnection = false
  @FocusState private var focusedField: Field?
  private enum Field { case login, password, server, database }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Email or username", text: $viewModel.login)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .textContentType(.username)
            .focused($focusedField, equals: .login).submitLabel(.next)
            .onSubmit { focusedField = .password }
          SecureField("Password", text: $viewModel.password)
            .textContentType(.password)
            .focused($focusedField, equals: .password).submitLabel(.go)
            .onSubmit { if !viewModel.isLoading { login() } }
        } header: { Text("Homestead Gristmill") }
        Section {
          if let error = viewModel.errorMessage {
            WorkplaceNotice(title: "Couldn’t sign in", message: error, symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
          }
          Button(action: login) {
            HStack {
              Text(viewModel.isLoading ? "Signing in…" : "Sign in")
              Spacer()
              if viewModel.isLoading { ProgressView().accessibilityHidden(true) }
            }.frame(minHeight: 44)
          }.disabled(viewModel.isLoading)
        }
        Section {
          DisclosureGroup("Connection settings", isExpanded: $showConnection) {
            TextField("Server URL", text: $serverURLText)
              .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
              .accessibilityLabel("Server URL")
              .focused($focusedField, equals: .server).submitLabel(.next)
              .onSubmit { focusedField = .database }
            TextField("Database", text: $config.database)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .focused($focusedField, equals: .database).submitLabel(.done)
              .onSubmit { focusedField = nil }
          }
        } footer: { if let host = config.baseURL?.host { Text(host) } }
      }
      .navigationTitle("Sign in")
      .navigationBarTitleDisplayMode(.inline)
    }
    .tint(WorkplaceTheme.accent)
    .scrollDismissesKeyboard(.interactively)
    .onChange(of: viewModel.errorMessage) { _, message in
      if let message { UIAccessibility.post(notification: .announcement, argument: "Couldn’t sign in. \(message)") }
    }
    .onAppear {
      if serverURLText.isEmpty {
        serverURLText = config.baseURL?.absoluteString ?? ""
      }
      if config.baseURL == nil { showConnection = true }
    }
    .sheet(isPresented: $viewModel.showCompanyPicker) {
      NavigationStack {
        List {
          if viewModel.isLoading { ProgressView("Opening your workplace…") }
          if let message = viewModel.errorMessage {
            WorkplaceNotice(title: "Couldn’t open this workplace", message: message,
                            symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
          }
          ForEach(viewModel.pendingCompanies) { company in
            Button {
              Task {
                await viewModel.selectCompany(
                  companyId: company.id,
                  serverURL: config.baseURL,
                  authStore: authStore
                )
              }
            } label: { WorkplaceActionLabel(title: company.name, subtitle: "Continue to this workplace", symbol: "building.2") }
            .disabled(viewModel.isLoading)
          }
        }
        .workplaceScreen().navigationTitle("Choose your workplace")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { viewModel.showCompanyPicker = false }.disabled(viewModel.isLoading)
          }
        }
        .interactiveDismissDisabled(viewModel.isLoading)
      }
    }
  }

  private func login() {
    focusedField = nil
    // Auto-fix URL scheme
    var urlString = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://")
    {
      urlString = "https://" + urlString
    }

    if let url = URL(string: urlString) {
      config.baseURL = url
    }
    Task {
      await viewModel.submit(
        serverURL: config.baseURL,
        database: config.database,
        authStore: authStore
      )
    }
  }
}
