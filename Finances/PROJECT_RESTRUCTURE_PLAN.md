# 🗂️ План реструктуризации проекта Finances

## Цель
Организовать проект по логическим модулям для улучшения читаемости и поддержки кода.

---

## 📋 Новая структура проекта

```
Finances/
├── App/
│   ├── FinancesApp.swift
│   └── RootTabView.swift
│
├── Models/
│   ├── Account.swift
│   ├── Transaction.swift
│   ├── Expense.swift
│   ├── ExpenseCategoryItem.swift
│   ├── CategoryRule.swift
│   ├── ExchangeRateEntry.swift
│   ├── TrackedExchangeRate.swift
│   ├── AppSettings.swift
│   └── TransactionTag.swift
│
├── Views/
│   ├── AddExpenseView.swift
│   ├── ContentView.swift
│   ├── TransactionsView.swift
│   ├── TransactionDetailView.swift
│   ├── AnalyticsView.swift
│   ├── InteractiveBarChartView.swift
│   ├── RulesView.swift
│   ├── BuiltInRulesView.swift
│   ├── AddRuleView.swift
│   ├── SettingsView.swift
│   ├── TagsManagementView.swift
│   └── AccountsView.swift (если существует)
│
├── Services/
│   ├── AccountBalanceCalculator.swift
│   ├── TransactionCategorySync.swift
│   ├── LegacyExpenseMigrator.swift
│   ├── DefaultAccountsSeeder.swift
│   ├── CategorySeeder.swift
│   ├── ExchangeRateStore.swift
│   ├── KaspiStatementParser.swift
│   ├── DataExportImportManager.swift
│   ├── BulkTaggingHelper.swift
│   ├── BuiltInCategoryRules.swift
│   └── (другие вспомогательные классы)
│
├── Tests/
│   ├── CategoryValidationTests.swift
│   └── FinancesUITests.swift
│
└── Resources/
    └── PROPORTIONAL_SCROLL_IMPLEMENTATION.md
```

---

## 🔧 Инструкции по реорганизации в Xcode

### Шаг 1: Создание Groups (папок)

1. В Xcode, в Project Navigator (⌘1), правый клик на корневую папку проекта `Finances`
2. Выберите **New Group**
3. Создайте следующие группы:
   - `App`
   - `Models`
   - `Views`
   - `Services`
   - `Tests`
   - `Resources`

### Шаг 2: Перемещение файлов

#### 📱 App (2 файла)
Перетащите следующие файлы в группу **App**:
- [ ] FinancesApp.swift
- [ ] RootTabView.swift

#### 🗄️ Models (9+ файлов)
Перетащите следующие файлы в группу **Models**:
- [ ] Account.swift
- [ ] Transaction.swift
- [ ] Expense.swift
- [ ] ExpenseCategoryItem.swift (найдите, если существует)
- [ ] CategoryRule.swift
- [ ] ExchangeRateEntry.swift (найдите, если существует)
- [ ] TrackedExchangeRate.swift (найдите, если существует)
- [ ] AppSettings.swift
- [ ] TransactionTag.swift (найдите, если существует)

#### 🎨 Views (10+ файлов)
Перетащите следующие файлы в группу **Views**:
- [ ] AddExpenseView.swift
- [ ] ContentView.swift
- [ ] TransactionsView.swift
- [ ] TransactionDetailView.swift
- [ ] AnalyticsView.swift
- [ ] InteractiveBarChartView.swift
- [ ] RulesView.swift
- [ ] BuiltInRulesView.swift
- [ ] AddRuleView.swift
- [ ] SettingsView.swift
- [ ] TagsManagementView.swift
- [ ] AccountsView.swift (если существует)
- [ ] AddTransactionView.swift (если существует)
- [ ] EditAccountView.swift (если существует)

#### ⚙️ Services (10+ файлов)
Перетащите следующие файлы в группу **Services**:
- [ ] AccountBalanceCalculator.swift
- [ ] TransactionCategorySync.swift
- [ ] LegacyExpenseMigrator.swift
- [ ] DefaultAccountsSeeder.swift
- [ ] CategorySeeder.swift
- [ ] ExchangeRateStore.swift
- [ ] KaspiStatementParser.swift
- [ ] DataExportImportManager.swift
- [ ] BulkTaggingHelper.swift
- [ ] BuiltInCategoryRules.swift
- [ ] ManualExpenseCurrencyConverter.swift (если существует)
- [ ] SupportedInputCurrencies.swift (если существует)
- [ ] TransactionSectionGrouper.swift (если существует)
- [ ] AnalyticsSnapshotBuilder.swift (если существует)
- [ ] AccountLookup.swift (если существует)
- [ ] DefaultCategoryDefinitions.swift (если существует)

#### 🧪 Tests (2 файла)
Перетащите следующие файлы в группу **Tests**:
- [ ] CategoryValidationTests.swift
- [ ] FinancesUITests.swift

#### 📄 Resources (документация)
Перетащите следующие файлы в группу **Resources**:
- [ ] PROPORTIONAL_SCROLL_IMPLEMENTATION.md
- [ ] PROJECT_RESTRUCTURE_PLAN.md (этот файл)

---

## ✅ Проверка после реорганизации

После перемещения файлов убедитесь, что:

1. ✅ Проект компилируется без ошибок (⌘B)
2. ✅ Все импорты работают корректно
3. ✅ Приложение запускается
4. ✅ Все функции работают как ожидается

---

## 💡 Рекомендации на будущее

### Дальнейшее разбиение (опционально)

Если проект будет расти, можно создать подпапки:

#### Models/
```
Models/
├── Core/
│   ├── Account.swift
│   ├── Transaction.swift
│   └── Expense.swift
├── Categories/
│   ├── ExpenseCategoryItem.swift
│   └── CategoryRule.swift
└── Settings/
    ├── AppSettings.swift
    └── TrackedExchangeRate.swift
```

#### Views/
```
Views/
├── Transactions/
│   ├── TransactionsView.swift
│   ├── TransactionDetailView.swift
│   └── AddExpenseView.swift
├── Analytics/
│   ├── AnalyticsView.swift
│   └── InteractiveBarChartView.swift
└── Settings/
    ├── SettingsView.swift
    ├── RulesView.swift
    └── TagsManagementView.swift
```

#### Services/
```
Services/
├── Calculators/
│   └── AccountBalanceCalculator.swift
├── Parsers/
│   └── KaspiStatementParser.swift
├── Migration/
│   └── LegacyExpenseMigrator.swift
└── Seeders/
    ├── DefaultAccountsSeeder.swift
    └── CategorySeeder.swift
```

---

## 🎯 Преимущества новой структуры

✅ **Понятная организация** — легко найти нужный файл
✅ **Масштабируемость** — удобно добавлять новые файлы
✅ **Разделение ответственности** — каждая папка имеет четкое назначение
✅ **Лучшая навигация** — быстрее ориентироваться в проекте
✅ **Командная работа** — проще работать в команде

---

## 📝 Примечания

- В Xcode группы (Groups) не обязательно соответствуют физическим папкам на диске
- Если хотите, чтобы Groups были настоящими папками, используйте опцию "New Group with Folder"
- Все файлы должны оставаться в target приложения

---

**Дата создания:** 27 апреля 2026
**Автор:** Ваш AI-помощник 🤖
