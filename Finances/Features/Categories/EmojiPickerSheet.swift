//
//  EmojiPickerSheet.swift
//  Finances
//
//  Created by Андрей Матиенко on 01.04.2026.
//


import SwiftUI

struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedEmoji: String

    private let sections: [EmojiSection] = [
        .init(
            title: "Смайлы и эмоции",
            emojis: ["😀","😃","😄","😁","😆","🥹","😂","🤣","😊","🙂","😉","😍","🥰","😘","😗","😙","😚","😋","😛","😜","🤪","🤨","🧐","🤓","😎","🥳","😏","😌","😔","🥲","😢","😭","😤","😠","😡","🤯","😳","🥺","😬","🤔","🫠","😴","🤤","🤗","🫡","🤐","🫢","🫣","😶","🫥"]
        ),
        .init(
            title: "Люди и жесты",
            emojis: ["👍","👎","👌","✌️","🤞","🤟","🤘","👏","🙌","🫶","🙏","💪","🫰","👋","🤝","🫵","👀","🧠","🫀","❤️","💔","🔥","⭐️","✨","💫","🎉","🎊","💯"]
        ),
        .init(
            title: "Еда и напитки",
            emojis: ["🍎","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍒","🥝","🍑","🥥","🥑","🍅","🥕","🌽","🥐","🍞","🧀","🥚","🍔","🍟","🍕","🌭","🌮","🌯","🥗","🍝","🍜","🍣","🍱","🍛","🍰","🧁","🍪","🍩","🍫","🍿","☕️","🍵","🥤","🧃","🍺","🍷"]
        ),
        .init(
            title: "Транспорт и места",
            emojis: ["🏠","🏡","🏨","🏢","🏙️","🛒","🛍️","🚗","🚕","🚌","🚇","✈️","🛫","🛬","⛽️","🗺️","🏖️","🏔️","🏝️","🏕️","🎡","🎢"]
        ),
        .init(
            title: "Активности",
            emojis: ["⚽️","🏀","🏐","🎾","🏓","🥊","🎮","🎯","🎲","🎸","🎹","🎧","🎬","🎨","📚","📖","🧩","🛏️","🧘","🏃","🚶","🐾","📞","📶"]
        ),
        .init(
            title: "Объекты",
            emojis: ["💳","💵","💴","💶","💷","💰","💎","🧳","💼","🩺","💊","🎁","📱","💻","⌚️","📷","🔑","🛜","💡","🧾","📌","🪪"]
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                    keyboardCard

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.headline)
                                .padding(.horizontal, 16)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                                spacing: 10
                            ) {
                                ForEach(section.emojis, id: \.self) { emoji in
                                    Button {
                                        selectedEmoji = emoji
                                        dismiss()
                                    } label: {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(.secondarySystemGroupedBackground))
                                            .frame(height: 52)
                                            .overlay {
                                                Text(emoji)
                                                    .font(.system(size: 28))
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Выбрать эмодзи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }

                if !selectedEmoji.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сбросить") {
                            selectedEmoji = ""
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

extension EmojiPickerSheet {
    /// Поле с системной клавиатурой эмодзи iPhone: все эмодзи и поиск по ним.
    private var keyboardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)

                SystemEmojiField { emoji in
                    selectedEmoji = emoji
                    dismiss()
                }
                .frame(height: 24)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Любой эмодзи с клавиатуры iPhone — со всеми категориями и поиском. Ниже — популярные.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
    }
}

/// Текстовое поле, которое открывает сразу клавиатуру эмодзи (если она включена в iOS)
/// и отдаёт первый введённый эмодзи.
struct SystemEmojiField: UIViewRepresentable {
    let onPick: (String) -> Void

    final class EmojiTextField: UITextField {
        override var textInputMode: UITextInputMode? {
            UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
        }
    }

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.placeholder = "Открыть клавиатуру эмодзи"
        field.font = .preferredFont(forTextStyle: .body)
        field.returnKeyType = .done
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ uiView: EmojiTextField, context: Context) {
        context.coordinator.onPick = onPick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onPick: (String) -> Void

        init(onPick: @escaping (String) -> Void) {
            self.onPick = onPick
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let emoji = string.first(where: \.isEmojiCharacter) {
                onPick(String(emoji))
            }
            return false
        }
    }
}

private extension Character {
    var isEmojiCharacter: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (unicodeScalars.count > 1 && first.properties.isEmoji)
    }
}

private struct EmojiSection: Identifiable {
    let id = UUID()
    let title: String
    let emojis: [String]
}