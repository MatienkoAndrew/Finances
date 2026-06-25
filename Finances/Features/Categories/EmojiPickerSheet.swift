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
    @State private var searchText: String = ""

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

    private var filteredSections: [EmojiSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }

        return sections.compactMap { section in
            let filtered = section.emojis.filter { emoji in
                emoji.localizedCaseInsensitiveContains(query)
            }
            return filtered.isEmpty ? nil : EmojiSection(title: section.title, emojis: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                    ForEach(filteredSections) { section in
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
            .searchable(text: $searchText, prompt: "Поиск")
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

private struct EmojiSection: Identifiable {
    let id = UUID()
    let title: String
    let emojis: [String]
}