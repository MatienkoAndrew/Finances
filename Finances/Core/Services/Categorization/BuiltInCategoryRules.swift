import Foundation

/// Встроенное правило автоматической категоризации
struct BuiltInCategoryRule: Identifiable {
    /// Как искать паттерн в названии мерчанта.
    enum MatchMode: String {
        /// Отдельным словом: «BAR» найдёт «ROOFTOP BAR», но не «BARBER».
        case word
        /// С начала слова: «7 11» найдёт «7 11TISCO».
        case wordPrefix
        /// Где угодно, без учёта пробелов: «COFFEE» найдёт «VNPAY ROOSTCOFFEE».
        case substring
    }

    let id: String
    let pattern: String
    let categoryName: String
    let subcategoryName: String?
    let matchMode: MatchMode
    let description: String
    var isEnabled: Bool
    /// Паттерн, подготовленный под `matchMode`, — чтобы не разбирать его на каждой операции.
    private let needle: String

    init(
        id: String,
        pattern: String,
        categoryName: String,
        subcategoryName: String? = nil,
        matchMode: MatchMode? = nil,
        description: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.pattern = pattern
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        // Короткие паттерны («CU», «BAR», «SPA») — только отдельным словом.
        let squashed = MerchantName.words(pattern).joined()
        let mode = matchMode ?? (squashed.count <= 4 ? .word : .substring)
        self.matchMode = mode
        self.description = description
        self.isEnabled = isEnabled

        let words = MerchantName.words(pattern)
        switch mode {
        case .word: needle = " " + words.joined(separator: " ") + " "
        case .wordPrefix: needle = " " + words.joined(separator: " ")
        case .substring: needle = squashed
        }
    }

    func matches(_ text: MerchantText) -> Bool {
        guard !needle.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return matchMode == .substring ? text.squashed.contains(needle) : text.padded.contains(needle)
    }
}

/// Название мерчанта, подготовленное для поиска паттернов.
struct MerchantText {
    /// « PAYOO MCDONALDS 0053A » — слова через пробел, с пробелами по краям.
    let padded: String
    /// «PAYOOMCDONALDS0053A» — без разделителей.
    let squashed: String

    init(_ details: String) {
        let words = MerchantName.words(details)
        padded = " " + words.joined(separator: " ") + " "
        squashed = words.joined()
    }
}

/// Менеджер встроенных правил категоризации
enum BuiltInCategoryRulesManager {
    private static let storageKey = "builtInCategoryRulesStates"

    /// Все доступные встроенные правила. Порядок важен: срабатывает первое подходящее,
    /// поэтому конкретные бренды идут раньше общих слов («GRABFOOD» раньше «GRAB»,
    /// «SPA» раньше «PHO»). Правило с категорией, которой у пользователя нет
    /// («Красота», «Комиссия», «Vpn»), пропускается — дальше идёт запасное.
    static let allRules: [BuiltInCategoryRule] = [
        // Комиссии банка
        group("Комиссия", nil, "Комиссии банка", ["КОМИССИЯ"]),

        // Доставка еды — раньше такси и ресторанов
        group("Еда", "Доставка", "Доставка еды", [
            "GRABFOOD", "WOLT", "GLOVO", "YANDEX EDA", "YANDEXEDA", "CHOCOFOOD", "FOODPANDA", "BAEMIN",
            "COUPANG EATS", "UBER EATS", "UBEREATS", "SHOPEEFOOD", "LINEMAN", "LINE MAN", "GOFOOD",
            "DOORDASH", "DELIVEROO", "DELIVERY CLUB", "YOGIYO"
        ]),

        // Продукты: супермаркеты и магазины у дома
        group("Продукты", nil, "Супермаркеты и магазины у дома", [
            "METRO CASH", "ARBUZ", "AIRBA FRESH", "MAGNUM", "SMALL", "GALMART", "ANVAR", "SPAR", "CARREFOUR",
            "LOTUS", "TOPS", "BIG C", "BIGC", "MAKRO", "WINMART", "COOPMART", "BACH HOA XANH", "LOTTE MART",
            "EMART", "HOMEPLUS", "AEON", "TESCO", "FOODLAND", "GOURMET MARKET", "WALMART", "COSTCO", "LIDL",
            "ALDI", "PYATEROCHKA", "PEREKRESTOK", "VKUSVILL", "AUCHAN",
            "7ELEVEN", "SEVEN ELEVEN", "CIRCLE K", "CIRCLEK", "FAMILYMART", "LAWSON", "MINISTOP", "GS25",
            "CU", "EMART24", "MINIMART", "SUPERMARKET", "GROCERY", "MART", "MARKET", "ПРОДУКТЫ", "МАГАЗИН"
        ]),
        [rule("Продукты", nil, "7-Eleven (Таиланд)", "7 11", mode: .wordPrefix)],

        // Фастфуд
        group("Еда", "Фастфуд", "Фастфуд", [
            "MCDONALDS", "MCD", "BURGER", "LOTTERIA", "JOLLIBEE", "POPEYES", "DOMINO", "PIZZA",
            "SALAM BRO", "HARDEES", "TACO", "SHAWARMA", "ШАУРМА", "DONER", "CHICKEN", "BANH MI", "HOTDOG",
            "HOT DOG", "DUNKIN"
        ]),
        [rule("Еда", "Фастфуд", "KFC", "KFC", mode: .substring)],

        // Кофейни, кафе, десерты
        group("Еда", "Кафе", "Кофейни и кафе", [
            "COFFEE", "KOFFEE", "KHOFFEE", "KEOPI", "KOPI", "CAFE", "CAFFE", "КАФЕ", "KAFE", "ESPRESSO",
            "ROASTER", "ROSTER", "STARBUCKS", "HIGHLANDS", "ARABICA", "TRUNG NGUYEN", "PHUC LONG", "CA PHE",
            "PHE LA", "GONG CHA", "CHATIME", "KOI THE", "MIXUE", "BUBBLE", "BOBA", "TEA", "DESSERT",
            "BAKERY", "BAKE", "BRUNCH", "PARIS BAGUETTE", "TOUS LES JOURS", "DONUT", "GELATO", "ICE CREAM"
        ]),

        // Бары
        group("Еда", "Бар", "Бары и пабы", [
            "BAR", "PUB", "TAPROOM", "BREW", "BEER", "HIGHBALL", "WINE", "COCKTAIL", "ROOFTOP", "IZAKAYA"
        ]),

        // Красота и уход — раньше ресторанов («SPA PHO CO»)
        group("Красота", nil, "Салоны красоты", ["SALON", "BARBER", "HAIR", "NAIL", "BEAUTY", "LASH", "BROW"]),
        group("Здоровье", "Косметолог", "Салоны красоты", ["SALON", "BARBER", "HAIR", "NAIL", "BEAUTY", "COSMETOLOG"]),
        group("Здоровье", "Массаж", "Массаж и спа", ["MASSAGE", "SPA", "WELLNESS"]),

        // Рестораны
        group("Еда", "Ресторан", "Рестораны", [
            "RESTAURANT", "RESTAUTANT", "RESTORAN", "РЕСТОРАН", "RESTO", "NHA HANG", "PHO", "BBQ", "GRILL",
            "STEAK", "SUSHI", "RAMEN", "KITCHEN", "BISTRO", "DINER", "CUISINE", "EATERY", "NOODLE", "DIMSUM",
            "BANH XEO", "SOMTUM", "SIKDANG", "GUKBAP", "BUNSIK", "GALBI", "ASHANA", "СТОЛОВАЯ", "STOLOVAYA"
        ]),

        // Такси
        group("Транспорт", "Такси", "Такси", [
            "GRAB", "YANDEX GO", "YANDEXGO", "YANDEX TAXI", "UBER", "BOLT", "INDRIVE", "GOJEK", "XANH SM",
            "MAI LINH", "VINASUN", "KAKAO MOBILITY", "KAKAOT", "TADA", "CABIFY", "LYFT", "ТАКСИ"
        ]),
        [rule("Транспорт", "Такси", "Такси", "TAXI", mode: .substring)],

        // Общественный транспорт
        group("Общественный транспорт", nil, "Метро, автобусы", ["BTS", "MRT", "METRO", "ONAY", "TMONEY", "BUS"]),
        group("Транспорт", "Общественный транспорт", "Метро, автобусы", [
            "BTS", "MRT", "METRO", "ONAY", "TMONEY", "T MONEY", "CASHBEE", "BUS", "ARL", "OCTOPUS",
            "EZ LINK", "EZLINK", "OPAL", "TRANSPORT CARD"
        ]),

        // Поезда
        group("Транспорт", "Поезд/электричка", "Поезда", [
            "SRT", "KTX", "KORAIL", "RAILWAY", "TEMIR ZHOLY", "KTZ", "TULPAR", "RAIL"
        ]),

        // Самокаты, велосипеды, байки, каршеринг
        group("Транспорт", "Самокат", "Самокаты", ["WHOOSH", "LIME", "JET SHARING", "URENT", "YANDEX SCOOTER", "SCOOTER"]),
        group("Транспорт", "Аренда велосипеда", "Велопрокат", ["BIKE SHARING", "MOBIKE", "TNGO", "ALMATY BIKE", "ASTANA BIKE"]),
        group("Аренда Байка", nil, "Аренда байка", ["MOTORBIKE", "BIKE RENT", "MOTO RENT"]),
        group("Транспорт", "Аренда байка", "Аренда байка", ["MOTORBIKE", "BIKE RENT", "MOTO RENT"]),
        group("Транспорт", "Каршеринг", "Каршеринг", ["ANYTIME", "DELIMOBIL", "BELKACAR", "YANDEX DRIVE", "SOCAR"]),

        // Заправки, парковки, дороги
        group("Транспорт", "Заправка", "Заправки", [
            "SHELL", "CALTEX", "PTT", "ESSO", "PETRO", "HELIOS", "SINOOIL", "SINO OIL", "KAZMUNAYGAS",
            "QAZAQ OIL", "GAZPROM", "LUKOIL", "ROSNEFT", "GAS STATION", "FUEL", "АЗС", "BANGCHAK", "CHEVRON",
            "SK ENERGY", "GS CALTEX"
        ]),
        group("Транспорт", "Парковка", "Парковки", ["PARKING", "ПАРКОВКА"]),
        group("Транспорт", "Платные дороги", "Платные дороги", ["TOLL", "EXPRESSWAY", "HIPASS"]),

        // Путешествия
        group("Путешествия", "Отели", "Отели и жильё в поездках", [
            "HOTEL", "HOSTEL", "BACKPACKERS", "RESORT", "HOMESTAY", "GUESTHOUSE", "GUEST HOUSE", "BOOKING",
            "AGODA", "AIRBNB", "EXPEDIA", "TRIP COM", "TRIPCOM", "OSTROVOK", "MOTEL", "INN", "NHA NGHI",
            "KHACH SAN", "LODGE"
        ]),
        group("Путешествия", "Авиабилеты", "Авиакомпании", [
            "AIRLINES", "AIRWAYS", "AIR ASTANA", "AIRASTANA", "FLYARYSTAN", "SCAT", "AIRASIA", "AIR ASIA",
            "VIETJET", "BAMBOO", "NOK AIR", "AEROFLOT", "POBEDA", "TURKISH AIR", "QATAR", "EMIRATES",
            "AVIASALES", "KIWI COM"
        ]),
        group("Путешествия", "Ж/д билеты", "Билеты на поезда и автобусы", ["12GO", "TUTU", "TRAINS", "BAOLAU"]),
        group("Путешествия", "Аренда авто", "Прокат авто", ["RENT A CAR", "RENTACAR", "HERTZ", "AVIS", "SIXT", "EUROPCAR"]),
        group("Путешествия", "Виза/страховка", "Визы и страховки", [
            "VISA", "EVISA", "INSURANCE", "STRAKHOV", "СТРАХОВ", "IMMIGRATION", "VFS"
        ]),
        group("Путешествия", "Экскурсии", "Экскурсии и развлечения в поездках", [
            "TOURS", "TRAVEL", "KLOOK", "GETYOURGUIDE", "VIATOR", "CABLE CAR", "CAP TREO", "MUSEUM",
            "SAFARI", "AQUARIUM", "ZOO"
        ]),

        // Здоровье
        group("Здоровье", "Аптека", "Аптеки", [
            "PHARMACY", "PHARMA", "APTEKA", "АПТЕКА", "DRUGSTORE", "DRUG STORE", "LONG CHAU", "PHARMACITY",
            "EUROPHARMA", "SADYKHAN"
        ]),
        group("Здоровье", "Стоматология", "Стоматология", ["DENTAL", "DENTIST", "СТОМАТ", "NHA KHOA"]),
        group("Здоровье", "Анализы", "Лаборатории", ["INVITRO", "OLYMP", "KDL", "LABORATOR"]),
        group("Здоровье", "Врач/клиника", "Клиники", [
            "CLINIC", "HOSPITAL", "MEDICAL", "MEDICINE", "MEDCENTER", "KLINIK", "КЛИНИК", "DOCTOR", "BENH VIEN"
        ]),
        group("Здоровье", "Спорт/фитнес", "Спорт и фитнес", [
            "FITNESS", "GYM", "WORLD CLASS", "INVICTUS", "CROSSFIT", "YOGA", "MUAY THAI", "BOXING", "SWIM"
        ]),

        // Подписки
        group("Подписки", "ИИ", "Нейросети", [
            "OPENAI", "CHATGPT", "ANTHROPIC", "CLAUDE AI", "MIDJOURNEY", "PERPLEXITY", "CURSOR", "COPILOT"
        ]),
        group("Подписки", "Музыка", "Музыка", [
            "SPOTIFY", "YANDEX PLUS", "YANDEX MUSIC", "APPLE MUSIC", "DEEZER", "TIDAL", "SOUNDCLOUD"
        ]),
        group("Подписки", "Облако", "Облачные хранилища", ["ICLOUD", "GOOGLE ONE", "DROPBOX"]),
        group("Подписки", "Связь", "Мобильная связь и eSIM", [
            "BEELINE", "KCELL", "ACTIV", "TELE2", "ALTEL", "IZI", "MEGAFON", "VIETTEL", "VINAPHONE", "MOBIFONE",
            "TRUEMOVE", "DTAC", "AIRALO", "HOLAFLY", "ESIM", "SIM CARD"
        ]),
        group("Vpn", nil, "VPN", ["VPN", "SURFSHARK", "PROTON"]),
        group("Подписки", "Другое", "Сервисы и приложения", [
            "VPN", "SURFSHARK", "APPLE COM BILL", "GOOGLE PLAY", "NETFLIX", "YOUTUBE", "KINOPOISK", "DISNEY",
            "HBO", "PRIME VIDEO", "TWITCH", "TELEGRAM", "NOTION", "FIGMA", "ADOBE", "MICROSOFT", "CANVA",
            "DUOLINGO"
        ]),

        // Покупки
        group("Покупки", "Подарки", "Подарки и цветы", ["GIFT", "FLOWER", "ЦВЕТЫ", "SOUVENIR"]),
        group("Покупки", "Маркетплейсы", "Маркетплейсы", [
            "WILDBERRIES", "OZON", "ALIEXPRESS", "AMAZON", "TEMU", "SHEIN", "SHOPEE", "LAZADA", "TIKI",
            "COUPANG", "TAOBAO", "EBAY", "ETSY", "LAMODA", "KASPI MAGAZIN"
        ]),
        group("Покупки", "Обувь", "Обувь", [
            "ASICS", "NIKE", "ADIDAS", "PUMA", "NEW BALANCE", "SKECHERS", "CROCS", "VANS", "CONVERSE", "SHOES"
        ]),
        group("Покупки", "Одежда", "Одежда", [
            "UNIQLO", "ZARA", "HENNES", "MANGO", "PULL BEAR", "BERSHKA", "STRADIVARIUS", "MASSIMO DUTTI",
            "LC WAIKIKI", "LCWAIKIKI", "COLINS", "GAP", "LEVI", "TOPSHOP", "DECATHLON", "SPORTMASTER"
        ]),
        group("Покупки", "Электроника", "Электроника", [
            "TECHNODOM", "SULPAK", "MECHTA", "ALSER", "DNS", "APPLE STORE", "ISTORE", "ISPACE", "SAMSUNG",
            "XIAOMI", "THE GIOI DI DONG", "DIEN MAY XANH", "FPT SHOP", "CELLPHONES", "BIC CAMERA", "YODOBASHI"
        ]),
        group("Покупки", "Дом/быт", "Товары для дома", ["IKEA", "LEROY MERLIN", "HOFF", "MUJI", "DAISO", "MINISO", "HOMEPRO"]),
        group("Покупки", "Косметика", "Косметика", [
            "SEPHORA", "OLIVE YOUNG", "OLIVEYOUNG", "WATSONS", "GOLDEN APPLE", "LETUAL", "HASAKI", "INNISFREE",
            "NATURE REPUBLIC", "COSMETIC"
        ]),
        group("Покупки", "Другое", "Книги и прочее", ["NHA SACH", "BOOKSTORE", "BOOKS", "ELEMENT"]),

        // Жильё
        group("Жильё", "Интернет", "Домашний интернет", ["KAZAKHTELECOM", "BEELINE HOME"]),
        group("Жильё", "Коммуналка", "Коммунальные платежи", ["ALSECO", "ЕРЦ", "ENERGOSBYT", "ВОДОКАНАЛ"]),

        // Развлечения — только если такая категория есть
        group("Развлечения", nil, "Кино, игры, досуг", [
            "CINEMA", "KINOPARK", "CHAPLIN", "CGV", "CINEPLEX", "STEAM", "PLAYSTATION", "NINTENDO", "BOWLING",
            "KARAOKE"
        ])
    ].flatMap { $0 }

    private static func rule(
        _ category: String,
        _ subcategory: String?,
        _ description: String,
        _ pattern: String,
        mode: BuiltInCategoryRule.MatchMode? = nil
    ) -> BuiltInCategoryRule {
        BuiltInCategoryRule(
            id: [category, subcategory ?? "", pattern].joined(separator: "/").lowercased(),
            pattern: pattern,
            categoryName: category,
            subcategoryName: subcategory,
            matchMode: mode,
            description: description
        )
    }

    private static func group(
        _ category: String,
        _ subcategory: String?,
        _ description: String,
        _ patterns: [String]
    ) -> [BuiltInCategoryRule] {
        patterns.map { rule(category, subcategory, description, $0, mode: modeOverrides[$0]) }
    }

    /// Исключения из правила «короткий паттерн — отдельным словом»: «MART» должен
    /// находить «4BMART» и «KOKOJIMART», а «SHELL» — не находить «SHELLFISH».
    private static let modeOverrides: [String: BuiltInCategoryRule.MatchMode] = [
        "MART": .substring, "CAFE": .substring, "КАФЕ": .substring, "GIFT": .substring,
        "BBQ": .substring, "BREW": .substring,
        "SMALL": .word, "ACTIV": .word, "METRO": .word, "SHELL": .word, "LOTUS": .word
    ]

    /// Загрузить состояния правил из UserDefaults
    static func loadStates() -> [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let states = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return states
    }

    /// Сохранить состояния правил в UserDefaults
    static func saveStates(_ states: [String: Bool]) {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        cachedActiveRules = nil
    }

    private static var cachedActiveRules: [BuiltInCategoryRule]?

    /// Получить активные правила с учётом настроек пользователя
    static func getActiveRules() -> [BuiltInCategoryRule] {
        if let cachedActiveRules { return cachedActiveRules }

        let states = loadStates()
        let active = allRules.map { rule in
            var mutableRule = rule
            if let savedState = states[rule.id] {
                mutableRule.isEnabled = savedState
            }
            return mutableRule
        }.filter { $0.isEnabled }
        cachedActiveRules = active
        return active
    }

    /// Обновить состояние конкретного правила
    static func updateRuleState(id: String, isEnabled: Bool) {
        var states = loadStates()
        states[id] = isEnabled
        saveStates(states)
    }
}
