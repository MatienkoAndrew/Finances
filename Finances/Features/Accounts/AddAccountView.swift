import SwiftUI
import SwiftData

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var currencyCode: String = "VND"
    @State private var selectedType: AccountType = .cash
    @State private var note: String = ""

    @State private var isShowingCurrencyPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Основная информация") {
                    TextField("Название", text: $name)

                    Button {
                        isShowingCurrencyPicker = true
                    } label: {
                        HStack {
                            Text("Валюта")
                                .foregroundStyle(.primary)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(CurrencyDisplay.title(for: currencyCode))
                                    .foregroundStyle(.primary)

                                Text(CurrencyDisplay.symbol(for: currencyCode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Picker("Тип", selection: $selectedType) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }

                    TextField("Заметка", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Новый счет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        saveAccount()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $isShowingCurrencyPicker) {
                CurrencyPickerView(selectedCode: currencyCode) { newCode in
                    currencyCode = newCode
                }
            }
            .onAppear {
                if name.isEmpty {
                    applySuggestedNameIfNeeded()
                }
            }
            .onChange(of: selectedType) { _, _ in
                applySuggestedNameIfNeeded()
            }
            .onChange(of: currencyCode) { _, _ in
                applySuggestedNameIfNeeded()
            }
        }
    }

    private func applySuggestedNameIfNeeded() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }

        switch selectedType {
        case .cash:
            name = "Cash \(CurrencyDisplay.normalizedCode(from: currencyCode))"
        case .bankCard:
            name = "Card \(CurrencyDisplay.normalizedCode(from: currencyCode))"
        case .bankAccount:
            name = "Account \(CurrencyDisplay.normalizedCode(from: currencyCode))"
        case .savings:
            name = "Savings \(CurrencyDisplay.normalizedCode(from: currencyCode))"
        case .other:
            name = CurrencyDisplay.normalizedCode(from: currencyCode)
        }
    }

    private func saveAccount() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let account = Account(
            name: trimmedName,
            currencyCode: CurrencyDisplay.normalizedCode(from: currencyCode),
            typeRaw: selectedType.rawValue,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )

        modelContext.insert(account)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save account: \(error)")
        }
    }
}
