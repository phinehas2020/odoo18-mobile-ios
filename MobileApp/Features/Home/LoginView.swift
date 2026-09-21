import SwiftUI

struct LoginView: View {
  @EnvironmentObject private var config: EnvironmentConfig
  @EnvironmentObject private var authStore: AuthStore

  @StateObject private var viewModel = LoginViewModel()
  @State private var serverURLText: String = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Odoo Mobile")
          .font(.largeTitle)
          .bold()

        Text("Sign in to your workplace").font(.title3).foregroundStyle(.secondary)

        Text("Connection").font(.headline)
        TextField("Server URL", text: $serverURLText)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          .autocorrectionDisabled()
          .textFieldStyle(.roundedBorder)

        TextField("Database", text: $config.database)
          .textInputAutocapitalization(.never)
          .textFieldStyle(.roundedBorder)

        Text("Your account").font(.headline)
        TextField("Login", text: $viewModel.login)
          .textInputAutocapitalization(.never)
          .textFieldStyle(.roundedBorder)

        SecureField("Password", text: $viewModel.password)
          .textContentType(.password)
          .textFieldStyle(.roundedBorder)

        if let error = viewModel.errorMessage {
          Text(error).foregroundColor(.red)
        }

        Button(action: login) {
          if viewModel.isLoading {
            ProgressView()
          } else {
            Text("Sign In")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(minHeight: 56)
        .disabled(viewModel.isLoading)

        Spacer()
      }
      .padding(24)
    }
    .onAppear {
      if serverURLText.isEmpty {
        serverURLText = config.baseURL?.absoluteString ?? ""
      }
    }
    .sheet(isPresented: $viewModel.showCompanyPicker) {
      NavigationStack {
        List(viewModel.pendingCompanies) { company in
          Button(company.name) {
            Task {
              await viewModel.selectCompany(
                companyId: company.id,
                serverURL: config.baseURL,
                authStore: authStore
              )
            }
          }
        }
        .navigationTitle("Select Company")
      }
    }
  }

  private func login() {
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
