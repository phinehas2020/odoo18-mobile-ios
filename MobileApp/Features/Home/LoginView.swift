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
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Homestead Gristmill").font(.title2.weight(.semibold))
          Text("Team app").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.top, 28).padding(.bottom, 8)

        VStack(alignment: .leading, spacing: 16) {
          Text("Sign in").font(.title2.weight(.semibold))
          VStack(alignment: .leading, spacing: 7) {
            Text("Email or username").font(.subheadline.weight(.medium))
            TextField("Login", text: $viewModel.login)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
              .textContentType(.username).textFieldStyle(.roundedBorder)
              .accessibilityLabel("Email or username")
              .focused($focusedField, equals: .login).submitLabel(.next)
              .onSubmit { focusedField = .password }
              .frame(minHeight: 44)
          }
          VStack(alignment: .leading, spacing: 7) {
            Text("Password").font(.subheadline.weight(.medium))
            SecureField("Password", text: $viewModel.password)
              .textContentType(.password).textFieldStyle(.roundedBorder).frame(minHeight: 44)
              .focused($focusedField, equals: .password).submitLabel(.go)
              .onSubmit { if !viewModel.isLoading { login() } }
          }

        if let error = viewModel.errorMessage {
          WorkplaceNotice(title: "Couldn’t sign in", message: error, symbol: "exclamationmark.circle", tint: WorkplaceTheme.danger)
        }

        Button(action: login) {
          HStack {
            if viewModel.isLoading { ProgressView().tint(.white).accessibilityHidden(true) }
            Text(viewModel.isLoading ? "Signing in…" : "Sign in")
          }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .workplaceProminentControl()
        .controlSize(.large)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity)
        .disabled(viewModel.isLoading)
        }
        .padding(20).background(WorkplaceTheme.surface, in: RoundedRectangle(cornerRadius: 16))

        VStack(alignment: .leading, spacing: 12) {
          if let host = config.baseURL?.host {
            Label(host, systemImage: "building.2").font(.subheadline).foregroundStyle(.secondary)
          }
          DisclosureGroup("Connection settings", isExpanded: $showConnection) {
            VStack(alignment: .leading, spacing: 12) {
              TextField("Server URL", text: $serverURLText)
                .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                .accessibilityLabel("Server URL")
                .focused($focusedField, equals: .server).submitLabel(.next)
                .onSubmit { focusedField = .database }
              TextField("Database", text: $config.database)
                .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                .focused($focusedField, equals: .database).submitLabel(.done)
                .onSubmit { focusedField = nil }
            }.padding(.top, 10)
          }.font(.subheadline)
        }.padding(.horizontal, 4)

        Spacer()
      }
      .padding(24)
    }
    .background(WorkplaceTheme.canvas).tint(WorkplaceTheme.accent)
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
