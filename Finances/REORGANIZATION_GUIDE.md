# 🎯 Пошаговая инструкция по реорганизации проекта в Xcode

## Часть 1: Создание структуры папок

### Шаг 1.1: Создание основных Groups

1. Откройте Xcode
2. В **Project Navigator** (⌘1) найдите корневую группу `Finances`
3. **Правый клик** на `Finances` → **New Group**
4. Назовите группу `App`
5. Повторите для остальных групп:
   - `Models`
   - `Views`
   - `Services`
   - `Tests`
   - `Resources`

### Результат должен выглядеть так:

```
Finances
├── App
├── Models
├── Views
├── Services
├── Tests
├── Resources
├── (все остальные файлы пока на месте)
```

---

## Часть 2: Перемещение файлов

### 📱 Группа: App

**Переместите эти 2 файла:**

1. Найдите файл `FinancesApp.swift`
2. **Перетащите** его в группу `App`
3. Найдите файл `RootTabView.swift`
4. **Перетащите** его в группу `App`

✅ **Чеклист:**
- [ ] FinancesApp.swift
- [ ] RootTabView.swift

---

### 🗄️ Группа: Models

**Переместите эти файлы:**

1. Account.swift
2. Transaction.swift
3. Expense.swift
4. CategoryRule.swift
5. AppSettings.swift

Если найдёте эти файлы, тоже перенесите:
- ExpenseCategoryItem.swift
- ExchangeRateEntry.swift
- TrackedExchangeRate.swift
- TransactionTag.swift

**Как искать отсутствующие файлы:**
- Нажмите ⌘⇧O (Open Quickly)
- Введите название, например `ExpenseCategoryItem`
- Если файл найден, откройте его и посмотрите, где он находится

✅ **Чеклист:**
- [ ] Account.swift
- [ ] Transaction.swift
- [ ] Expense.swift
- [ ] CategoryRule.swift
- [ ] AppSettings.swift
- [ ] ExpenseCategoryItem.swift (если есть)
- [ ] ExchangeRateEntry.swift (если есть)
- [ ] TrackedExchangeRate.swift (если есть)
- [ ] TransactionTag.swift (если есть)

---

### 🎨 Группа: Views

**Переместите все файлы, заканчивающиеся на `View.swift`:**

1. AddExpenseView.swift ⭐ **(это файл, который вы сейчас редактируете)**
2. ContentView.swift
3. TransactionsView.swift
4. TransactionDetailView.swift
5. AnalyticsView.swift
6. InteractiveBarChartView.swift
7. RulesView.swift
8. BuiltInRulesView.swift
9. AddRuleView.swift
10. SettingsView.swift
11. TagsManagementView.swift

Также проверьте наличие:
- AccountsView.swift (упоминается в RootTabView)
- AddTransactionView.swift
- EditAccountView.swift

✅ **Чеклист:**
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
- [ ] AccountsView.swift (если есть)
- [ ] AddTransactionView.swift (если есть)
- [ ] EditAccountView.swift (если есть)

---

### ⚙️ Группа: Services

**Переместите все утилиты и сервисы:**

1. AccountBalanceCalculator.swift
2. TransactionCategorySync.swift
3. LegacyExpenseMigrator.swift
4. DefaultAccountsSeeder.swift
5. CategorySeeder.swift
6. ExchangeRateStore.swift
7. KaspiStatementParser.swift
8. DataExportImportManager.swift
9. BulkTaggingHelper.swift
10. BuiltInCategoryRules.swift

Также проверьте наличие:
- ManualExpenseCurrencyConverter.swift (используется в AddExpenseView)
- SupportedInputCurrencies.swift (используется в AddExpenseView)
- TransactionSectionGrouper.swift (используется в TransactionsView)
- AnalyticsSnapshotBuilder.swift (используется в AnalyticsView)
- AccountLookup.swift (используется в LegacyExpenseMigrator)
- DefaultCategoryDefinitions.swift (используется в CategorySeeder)

✅ **Чеклист:**
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
- [ ] ManualExpenseCurrencyConverter.swift (если есть)
- [ ] SupportedInputCurrencies.swift (если есть)
- [ ] TransactionSectionGrouper.swift (если есть)
- [ ] AnalyticsSnapshotBuilder.swift (если есть)
- [ ] AccountLookup.swift (если есть)
- [ ] DefaultCategoryDefinitions.swift (если есть)

---

### 🧪 Группа: Tests

**Переместите тестовые файлы:**

1. CategoryValidationTests.swift
2. FinancesUITests.swift

✅ **Чеклист:**
- [ ] CategoryValidationTests.swift
- [ ] FinancesUITests.swift

---

### 📄 Группа: Resources

**Переместите документацию и ресурсы:**

1. PROPORTIONAL_SCROLL_IMPLEMENTATION.md
2. PROJECT_RESTRUCTURE_PLAN.md
3. CURRENT_PROJECT_STRUCTURE.md
4. REORGANIZATION_GUIDE.md (этот файл)

✅ **Чеклист:**
- [ ] PROPORTIONAL_SCROLL_IMPLEMENTATION.md
- [ ] PROJECT_RESTRUCTURE_PLAN.md
- [ ] CURRENT_PROJECT_STRUCTURE.md
- [ ] REORGANIZATION_GUIDE.md

---

## Часть 3: Проверка

### После перемещения всех файлов:

1. **Соберите проект** (⌘B)
   - Должна пройти компиляция без ошибок
   - Если есть ошибки — проверьте, что все файлы на месте

2. **Запустите приложение** (⌘R)
   - Проверьте основной функционал
   - Убедитесь, что все экраны открываются

3. **Проверьте структуру:**

```
Finances
├── App (2 файла)
│   ├── FinancesApp.swift
│   └── RootTabView.swift
│
├── Models (5-9 файлов)
│   ├── Account.swift
│   ├── Transaction.swift
│   ├── Expense.swift
│   ├── CategoryRule.swift
│   ├── AppSettings.swift
│   └── ...
│
├── Views (11+ файлов)
│   ├── AddExpenseView.swift
│   ├── ContentView.swift
│   ├── TransactionsView.swift
│   └── ...
│
├── Services (10+ файлов)
│   ├── AccountBalanceCalculator.swift
│   ├── TransactionCategorySync.swift
│   └── ...
│
├── Tests (2 файла)
│   ├── CategoryValidationTests.swift
│   └── FinancesUITests.swift
│
└── Resources (4 файла)
    ├── PROPORTIONAL_SCROLL_IMPLEMENTATION.md
    ├── PROJECT_RESTRUCTURE_PLAN.md
    ├── CURRENT_PROJECT_STRUCTURE.md
    └── REORGANIZATION_GUIDE.md
```

---

## Часть 4: Финализация

### Сохранение изменений в Git

```bash
# Добавьте все изменения
git add .

# Создайте коммит
git commit -m "♻️ Реорганизовать структуру проекта по логическим модулям

- Создана папка App для главных файлов приложения
- Создана папка Models для всех моделей данных
- Создана папка Views для всех SwiftUI views
- Создана папка Services для бизнес-логики и утилит
- Создана папка Tests для тестов
- Создана папка Resources для документации

Улучшена читаемость и навигация в проекте."

# Отправьте в репозиторий (опционально)
git push
```

---

## 💡 Советы

### Быстрое перемещение файлов

**Способ 1: Drag & Drop**
- Просто перетаскивайте файлы мышкой

**Способ 2: Cut & Paste**
1. Выберите файл
2. ⌘X (вырезать)
3. Выберите целевую группу
4. ⌘V (вставить)

**Способ 3: Множественный выбор**
1. Удерживайте ⌘
2. Кликайте на несколько файлов
3. Перетащите их все вместе

### Если что-то пошло не так

**Отмена последнего действия:**
- ⌘Z — отменить последнее перемещение

**Вернуть всё как было:**
- В Git: `git checkout .`
- В Xcode: File → Source Control → Discard All Changes

---

## ✅ Итоговый чеклист

- [ ] Создал все 6 основных групп (App, Models, Views, Services, Tests, Resources)
- [ ] Переместил все файлы согласно инструкции
- [ ] Проверил, что проект компилируется (⌘B)
- [ ] Проверил, что приложение запускается (⌘R)
- [ ] Проверил основной функционал
- [ ] Закоммитил изменения в Git
- [ ] Удалил старые файлы документации (если они дублируются)

---

## 🎉 Поздравляю!

Ваш проект теперь организован и структурирован!

**Преимущества:**
- ✅ Легко найти нужный файл
- ✅ Понятная архитектура
- ✅ Готов к масштабированию
- ✅ Лучше для командной работы

---

**Дата создания:** 27 апреля 2026
**Время на выполнение:** ~15-20 минут
