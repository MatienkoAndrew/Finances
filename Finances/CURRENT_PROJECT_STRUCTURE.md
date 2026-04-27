# 📊 Текущая структура проекта Finances

## Обнаруженные файлы (31 файл)

### Текущее состояние (без организации)

```
Finances/
├── Account.swift
├── AccountBalanceCalculator.swift
├── AddExpenseView.swift
├── AddRuleView.swift
├── AnalyticsView.swift
├── AppSettings.swift
├── BuiltInCategoryRules.swift
├── BuiltInRulesView.swift
├── BulkTaggingHelper.swift
├── CategoryRule.swift
├── CategorySeeder.swift
├── CategoryValidationTests.swift
├── ContentView.swift
├── DataExportImportManager.swift
├── DefaultAccountsSeeder.swift
├── ExchangeRateStore.swift
├── Expense.swift
├── FinancesApp.swift
├── FinancesUITests.swift
├── InteractiveBarChartView.swift
├── KaspiStatementParser.swift
├── LegacyExpenseMigrator.swift
├── PROPORTIONAL_SCROLL_IMPLEMENTATION.md
├── RootTabView.swift
├── RulesView.swift
├── SettingsView.swift
├── TagsManagementView.swift
├── Transaction.swift
├── TransactionCategorySync.swift
├── TransactionDetailView.swift
└── TransactionsView.swift
```

---

## 🔍 Анализ по категориям

### 📱 App Files (2)
- FinancesApp.swift
- RootTabView.swift

### 🗄️ Models (5 найдено, ~9 ожидается)
- Account.swift
- Transaction.swift
- Expense.swift
- CategoryRule.swift
- AppSettings.swift
- *(ExpenseCategoryItem.swift — не найден явно)*
- *(ExchangeRateEntry.swift — не найден явно)*
- *(TrackedExchangeRate.swift — не найден явно)*
- *(TransactionTag.swift — не найден явно)*

### 🎨 Views (11)
- AddExpenseView.swift ⭐ (текущий файл)
- ContentView.swift
- TransactionsView.swift
- TransactionDetailView.swift
- AnalyticsView.swift
- InteractiveBarChartView.swift
- RulesView.swift
- BuiltInRulesView.swift
- AddRuleView.swift
- SettingsView.swift
- TagsManagementView.swift

### ⚙️ Services/Utilities (10)
- AccountBalanceCalculator.swift
- TransactionCategorySync.swift
- LegacyExpenseMigrator.swift
- DefaultAccountsSeeder.swift
- CategorySeeder.swift
- ExchangeRateStore.swift
- KaspiStatementParser.swift
- DataExportImportManager.swift
- BulkTaggingHelper.swift
- BuiltInCategoryRules.swift

### 🧪 Tests (2)
- CategoryValidationTests.swift
- FinancesUITests.swift

### 📄 Documentation (1)
- PROPORTIONAL_SCROLL_IMPLEMENTATION.md

---

## 📈 Статистика

| Категория | Количество файлов |
|-----------|-------------------|
| App | 2 |
| Models | 5+ |
| Views | 11 |
| Services | 10 |
| Tests | 2 |
| Docs | 1 |
| **Всего** | **31+** |

---

## 🎯 Следующие шаги

1. Создать структуру Groups в Xcode
2. Переместить файлы согласно плану (см. PROJECT_RESTRUCTURE_PLAN.md)
3. Проверить компиляцию
4. Закоммитить изменения в Git

---

**Дата анализа:** 27 апреля 2026
