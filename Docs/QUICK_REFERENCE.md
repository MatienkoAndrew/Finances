# ⚡ Быстрая шпаргалка по реорганизации

## 1️⃣ Создать Groups (⌘⇧N на группе)

```
App
Models
Views
Services
Tests
Resources
```

---

## 2️⃣ Переместить файлы (Drag & Drop)

### 📱 App (2)
```
FinancesApp.swift
RootTabView.swift
```

### 🗄️ Models (5+)
```
Account.swift
Transaction.swift
Expense.swift
CategoryRule.swift
AppSettings.swift
+ ExpenseCategoryItem.swift
+ ExchangeRateEntry.swift
+ TrackedExchangeRate.swift
+ TransactionTag.swift
```

### 🎨 Views (11+)
```
AddExpenseView.swift ⭐
ContentView.swift
TransactionsView.swift
TransactionDetailView.swift
AnalyticsView.swift
InteractiveBarChartView.swift
RulesView.swift
BuiltInRulesView.swift
AddRuleView.swift
SettingsView.swift
TagsManagementView.swift
+ AccountsView.swift
```

### ⚙️ Services (10+)
```
AccountBalanceCalculator.swift
TransactionCategorySync.swift
LegacyExpenseMigrator.swift
DefaultAccountsSeeder.swift
CategorySeeder.swift
ExchangeRateStore.swift
KaspiStatementParser.swift
DataExportImportManager.swift
BulkTaggingHelper.swift
BuiltInCategoryRules.swift
+ ManualExpenseCurrencyConverter.swift
+ SupportedInputCurrencies.swift
+ TransactionSectionGrouper.swift
+ AnalyticsSnapshotBuilder.swift
+ AccountLookup.swift
+ DefaultCategoryDefinitions.swift
```

### 🧪 Tests (2)
```
CategoryValidationTests.swift
FinancesUITests.swift
```

### 📄 Resources (4)
```
PROPORTIONAL_SCROLL_IMPLEMENTATION.md
PROJECT_RESTRUCTURE_PLAN.md
CURRENT_PROJECT_STRUCTURE.md
REORGANIZATION_GUIDE.md
```

---

## 3️⃣ Проверить

```
⌘B — Build
⌘R — Run
```

---

## 4️⃣ Git

```bash
git add .
git commit -m "♻️ Реорганизовать структуру проекта"
git push
```

---

## 🔧 Горячие клавиши

| Действие | Клавиша |
|----------|---------|
| Project Navigator | ⌘1 |
| Open Quickly | ⌘⇧O |
| New Group | ⌘⇧N |
| Cut | ⌘X |
| Paste | ⌘V |
| Undo | ⌘Z |
| Build | ⌘B |
| Run | ⌘R |

---

## 🎯 Время выполнения: 15-20 минут

---

⭐ **Текущий файл:** AddExpenseView.swift → переместить в **Views**
