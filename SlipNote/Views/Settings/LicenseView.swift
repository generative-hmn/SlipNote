import SwiftUI

struct LicenseView: View {
    var showContinueButton: Bool = false
    var onContinue: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App Info
                    VStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Text("SlipNote")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("gamzabi@me.com")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    Divider()

                    // Open Source Licenses
                    Text("Open Source Licenses", comment: "License section header")
                        .font(.headline)

                    // GRDB License
                    licenseSection(
                        name: "GRDB.swift",
                        url: "https://github.com/groue/GRDB.swift",
                        license: grdbLicense
                    )

                    // HotKey License
                    licenseSection(
                        name: "HotKey",
                        url: "https://github.com/soffes/HotKey",
                        license: hotKeyLicense
                    )
                }
                .padding(24)
            }

            if showContinueButton {
                Divider()
                Button(action: {
                    onContinue?()
                }) {
                    Text("Continue", comment: "Continue button")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(20)
            }
        }
    }

    private func licenseSection(name: String, url: String, license: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Link(destination: URL(string: url)!) {
                    Image(systemName: "link")
                        .font(.caption)
                }
            }

            Text(license)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
        }
    }

    // MARK: - License Texts

    private let grdbLicense = """
MIT License

Copyright (C) 2015-2024 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

    private let hotKeyLicense = """
MIT License

Copyright (c) 2017-2024 Sam Soffes

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
}

// MARK: - First Launch License Window

struct FirstLaunchLicenseView: View {
    @Binding var isPresented: Bool

    var body: some View {
        LicenseView(showContinueButton: true) {
            AppSettings.shared.hasSeenLicense = true
            isPresented = false
        }
        .frame(width: 500, height: 600)
    }
}

#Preview {
    LicenseView(showContinueButton: true) {}
}
