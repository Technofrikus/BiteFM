import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var apiClient: APIClient
    @AppStorage("savedUsername") private var savedUsername = ""
    
    @State private var username = ""
    @State private var password = ""
    @State private var rememberCredentials = true
    @State private var didLoadSavedCredentials = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image("Logo", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
            
            Text("BiteFM")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Bitte logge dich ein, um das Archiv zu nutzen.")
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                TextField("E-Mail / Benutzername", text: $username)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Passwort", text: $password)
                    .textFieldStyle(.roundedBorder)

                Toggle("Logindaten merken", isOn: $rememberCredentials)
                
                if let errorMessage = apiClient.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button("Anmelden") {
                    Task {
                        await apiClient.login(username: username, password: password)
                        persistCredentialsIfNeeded()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                .disabled(username.isEmpty || password.isEmpty)
            }
            .frame(maxWidth: 300)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear(perform: loadSavedCredentialsIfNeeded)
    }

    private func loadSavedCredentialsIfNeeded() {
        guard !didLoadSavedCredentials else { return }
        didLoadSavedCredentials = true

        if !savedUsername.isEmpty {
            username = savedUsername
            password = KeychainHelper.readPassword(account: savedUsername) ?? ""
            rememberCredentials = true
        } else {
            rememberCredentials = false
        }
    }

    private func persistCredentialsIfNeeded() {
        guard apiClient.isLoggedIn else { return }

        if rememberCredentials {
            savedUsername = username
            KeychainHelper.savePassword(password, account: username)
        } else {
            if !savedUsername.isEmpty {
                KeychainHelper.deletePassword(account: savedUsername)
            }
            KeychainHelper.deletePassword(account: username)
            savedUsername = ""
        }
    }
}
