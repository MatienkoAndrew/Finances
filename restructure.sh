#!/usr/bin/env bash
#
# restructure.sh — переносит файлы проекта Finances в новую структуру.
#
# Безопасность:
#   - Использует `git mv`, поэтому история каждого файла сохраняется (`git log --follow`).
#   - Падает, если рабочее дерево грязное (есть несохранённые изменения).
#   - Поддерживает dry-run: ./restructure.sh --dry-run
#   - Идемпотентен: уже перенесённые файлы пропускаются с пометкой "skip".
#
# Применимо к Xcode 16+ с PBXFileSystemSynchronizedRootGroup —
# project.pbxproj править не нужно, Xcode подхватит структуру сам.
#
# Использование:
#   cd <корень репо, где лежит Finances.xcodeproj>
#   ./restructure.sh --dry-run     # посмотреть, что произойдёт
#   ./restructure.sh                # выполнить

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "=== DRY RUN — никакие файлы не будут перемещены ==="
fi

# Должны находиться в корне репо
if [ ! -d "Finances.xcodeproj" ] || [ ! -d "Finances" ]; then
    echo "Error: запусти скрипт из корня репозитория (там, где лежит Finances.xcodeproj)."
    exit 1
fi

# Проверка чистоты рабочего дерева (только если не dry-run)
if [ "$DRY_RUN" -eq 0 ]; then
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        echo "Error: в рабочем дереве есть несохранённые изменения."
        echo "Сделай commit или stash, прежде чем запускать."
        exit 1
    fi
fi

SRC="Finances"

# Helper: переместить файл, если он существует и ещё не перенесён.
gmv() {
    local from="$1"
    local to="$2"

    if [ ! -f "$from" ]; then
        if [ -f "$to" ]; then
            echo "  ok (already moved): $from"
        else
            echo "  skip (not found):   $from"
        fi
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would move: $from -> $to"
        return 0
    fi

    mkdir -p "$(dirname "$to")"
    git mv "$from" "$to"
    echo "  moved: $from -> $to"
}

mkd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would mkdir: $1"
    else
        mkdir -p "$1"
    fi
}

echo ""
echo "=== 1. Создаём дерево директорий ==="
mkd "Docs"
mkd "$SRC/App"
mkd "$SRC/Core/Models/Legacy"
mkd "$SRC/Core/Enums"
mkd "$SRC/Core/Persistence/Seeders"
mkd "$SRC/Core/Persistence/Migrations"
mkd "$SRC/Core/Services/Currency"
mkd "$SRC/Core/Services/Categorization"
mkd "$SRC/Core/Services/Accounts"
mkd "$SRC/Core/Services/Transactions"
mkd "$SRC/Core/Services/ImportExport"
mkd "$SRC/Features/Transactions/List"
mkd "$SRC/Features/Transactions/Detail"
mkd "$SRC/Features/Transactions/Add"
mkd "$SRC/Features/Expenses"
mkd "$SRC/Features/Accounts"
mkd "$SRC/Features/Categories"
mkd "$SRC/Features/Rules"
mkd "$SRC/Features/Tags"
mkd "$SRC/Features/Analytics/Models"
mkd "$SRC/Features/Currencies"
mkd "$SRC/Features/Settings"
mkd "$SRC/Shared/Components"
mkd "$SRC/Shared/Extensions"

echo ""
echo "=== 2. Документацию (.md) поднимаем в /Docs на корне ==="
gmv "$SRC/README.md"                              "Docs/README.md"
gmv "$SRC/REORGANIZATION_GUIDE.md"                "Docs/REORGANIZATION_GUIDE.md"
gmv "$SRC/PROJECT_RESTRUCTURE_PLAN.md"            "Docs/PROJECT_RESTRUCTURE_PLAN.md"
gmv "$SRC/QUICK_REFERENCE.md"                     "Docs/QUICK_REFERENCE.md"
gmv "$SRC/VISUAL_BEFORE_AFTER.md"                 "Docs/VISUAL_BEFORE_AFTER.md"
gmv "$SRC/IMPROVEMENTS_SUMMARY.md"                "Docs/IMPROVEMENTS_SUMMARY.md"
gmv "$SRC/CATEGORY_VALIDATION_CHANGES.md"         "Docs/CATEGORY_VALIDATION_CHANGES.md"
gmv "$SRC/PROPORTIONAL_SCROLL_IMPLEMENTATION.md"  "Docs/PROPORTIONAL_SCROLL_IMPLEMENTATION.md"
gmv "$SRC/TESTING_INSTRUCTIONS.md"                "Docs/TESTING_INSTRUCTIONS.md"
gmv "$SRC/CURRENT_PROJECT_STRUCTURE.md"           "Docs/CURRENT_PROJECT_STRUCTURE.md"

echo ""
echo "=== 3. Тест в правильный таргет ==="
gmv "$SRC/CategoryValidationTests.swift"          "FinancesTests/CategoryValidationTests.swift"

echo ""
echo "=== 4. App entry points ==="
gmv "$SRC/FinancesApp.swift"                      "$SRC/App/FinancesApp.swift"
gmv "$SRC/RootTabView.swift"                      "$SRC/App/RootTabView.swift"
gmv "$SRC/ContentView.swift"                      "$SRC/App/ContentView.swift"

echo ""
echo "=== 5. Core/Models — SwiftData @Model сущности ==="
gmv "$SRC/Account.swift"                          "$SRC/Core/Models/Account.swift"
gmv "$SRC/Transaction.swift"                      "$SRC/Core/Models/Transaction.swift"
gmv "$SRC/TransactionTag.swift"                   "$SRC/Core/Models/TransactionTag.swift"
gmv "$SRC/ExpenseCategoryItem.swift"              "$SRC/Core/Models/ExpenseCategoryItem.swift"
gmv "$SRC/CategoryRule.swift"                     "$SRC/Core/Models/CategoryRule.swift"
gmv "$SRC/AppSettings.swift"                      "$SRC/Core/Models/AppSettings.swift"
gmv "$SRC/ExchangeRateEntry.swift"                "$SRC/Core/Models/ExchangeRateEntry.swift"
gmv "$SRC/TrackedExchangeRate.swift"              "$SRC/Core/Models/TrackedExchangeRate.swift"
gmv "$SRC/Item.swift"                             "$SRC/Core/Models/Item.swift"
# Legacy
gmv "$SRC/Expense.swift"                          "$SRC/Core/Models/Legacy/Expense.swift"

echo ""
echo "=== 6. Core/Enums — value-типы и перечисления ==="
gmv "$SRC/CashFlowType.swift"                     "$SRC/Core/Enums/CashFlowType.swift"
gmv "$SRC/PriorityLevel.swift"                    "$SRC/Core/Enums/PriorityLevel.swift"
gmv "$SRC/SupportedCurrency.swift"                "$SRC/Core/Enums/SupportedCurrency.swift"
gmv "$SRC/SupportedInputCurrencies.swift"         "$SRC/Core/Enums/SupportedInputCurrencies.swift"
gmv "$SRC/SupportedTrackedCurrency.swift"         "$SRC/Core/Enums/SupportedTrackedCurrency.swift"
gmv "$SRC/TransactionKindFilter.swift"            "$SRC/Core/Enums/TransactionKindFilter.swift"
gmv "$SRC/ExpenseFilter.swift"                    "$SRC/Core/Enums/ExpenseFilter.swift"
gmv "$SRC/DateRangeSelection.swift"               "$SRC/Core/Enums/DateRangeSelection.swift"
gmv "$SRC/MonthSelection.swift"                   "$SRC/Core/Enums/MonthSelection.swift"

echo ""
echo "=== 7. Core/Persistence/Seeders ==="
gmv "$SRC/CategorySeeder.swift"                   "$SRC/Core/Persistence/Seeders/CategorySeeder.swift"
gmv "$SRC/DefaultAccountsSeeder.swift"            "$SRC/Core/Persistence/Seeders/DefaultAccountsSeeder.swift"
gmv "$SRC/DefaultCategories.swift"                "$SRC/Core/Persistence/Seeders/DefaultCategories.swift"
gmv "$SRC/DefaultCategoryDefinitions.swift"       "$SRC/Core/Persistence/Seeders/DefaultCategoryDefinitions.swift"
gmv "$SRC/DefaultTrackedCurrenciesSeeder.swift"   "$SRC/Core/Persistence/Seeders/DefaultTrackedCurrenciesSeeder.swift"

echo ""
echo "=== 8. Core/Persistence/Migrations ==="
gmv "$SRC/LegacyExpenseMigrator.swift"            "$SRC/Core/Persistence/Migrations/LegacyExpenseMigrator.swift"
gmv "$SRC/ExpenseRubRecalculator.swift"           "$SRC/Core/Persistence/Migrations/ExpenseRubRecalculator.swift"
gmv "$SRC/TransactionRubRecalculator.swift"       "$SRC/Core/Persistence/Migrations/TransactionRubRecalculator.swift"
gmv "$SRC/TransactionCategorySync.swift"          "$SRC/Core/Persistence/Migrations/TransactionCategorySync.swift"

echo ""
echo "=== 9. Core/Services/Currency ==="
gmv "$SRC/CurrencyConverter.swift"                "$SRC/Core/Services/Currency/CurrencyConverter.swift"
gmv "$SRC/HistoricalCurrencyConverter.swift"      "$SRC/Core/Services/Currency/HistoricalCurrencyConverter.swift"
gmv "$SRC/ManualExpenseCurrencyConverter.swift"   "$SRC/Core/Services/Currency/ManualExpenseCurrencyConverter.swift"
gmv "$SRC/TransactionRubConverter.swift"          "$SRC/Core/Services/Currency/TransactionRubConverter.swift"
gmv "$SRC/ExchangeRateService.swift"              "$SRC/Core/Services/Currency/ExchangeRateService.swift"
gmv "$SRC/ExchangeRateStore.swift"                "$SRC/Core/Services/Currency/ExchangeRateStore.swift"

echo ""
echo "=== 10. Core/Services/Categorization ==="
gmv "$SRC/CategoryRuleEngine.swift"               "$SRC/Core/Services/Categorization/CategoryRuleEngine.swift"
gmv "$SRC/BuiltInCategoryRules.swift"             "$SRC/Core/Services/Categorization/BuiltInCategoryRules.swift"
gmv "$SRC/ExpenseCategoryGuesser.swift"           "$SRC/Core/Services/Categorization/ExpenseCategoryGuesser.swift"
gmv "$SRC/CategoryNameNormalizer.swift"           "$SRC/Core/Services/Categorization/CategoryNameNormalizer.swift"
gmv "$SRC/CategoryLookup.swift"                   "$SRC/Core/Services/Categorization/CategoryLookup.swift"
gmv "$SRC/BulkTaggingHelper.swift"                "$SRC/Core/Services/Categorization/BulkTaggingHelper.swift"

echo ""
echo "=== 11. Core/Services/Accounts ==="
gmv "$SRC/AccountBalanceCalculator.swift"         "$SRC/Core/Services/Accounts/AccountBalanceCalculator.swift"
gmv "$SRC/AccountLookup.swift"                    "$SRC/Core/Services/Accounts/AccountLookup.swift"

echo ""
echo "=== 12. Core/Services/Transactions ==="
gmv "$SRC/TransactionSectionGrouper.swift"        "$SRC/Core/Services/Transactions/TransactionSectionGrouper.swift"

echo ""
echo "=== 13. Core/Services/ImportExport ==="
gmv "$SRC/DataExportImportManager.swift"          "$SRC/Core/Services/ImportExport/DataExportImportManager.swift"
gmv "$SRC/PDFImporter.swift"                      "$SRC/Core/Services/ImportExport/PDFImporter.swift"
gmv "$SRC/PDFImportResult.swift"                  "$SRC/Core/Services/ImportExport/PDFImportResult.swift"
gmv "$SRC/PDFTextExtractor.swift"                 "$SRC/Core/Services/ImportExport/PDFTextExtractor.swift"
gmv "$SRC/PDFLayoutTextExtractor.swift"           "$SRC/Core/Services/ImportExport/PDFLayoutTextExtractor.swift"
gmv "$SRC/KaspiStatementParser.swift"             "$SRC/Core/Services/ImportExport/KaspiStatementParser.swift"

echo ""
echo "=== 14. Features/Transactions ==="
gmv "$SRC/TransactionsView.swift"                       "$SRC/Features/Transactions/List/TransactionsView.swift"
gmv "$SRC/TransactionRowView.swift"                     "$SRC/Features/Transactions/List/TransactionRowView.swift"
gmv "$SRC/TransactionListByCategoryView.swift"          "$SRC/Features/Transactions/List/TransactionListByCategoryView.swift"
gmv "$SRC/TransactionListByDateView.swift"              "$SRC/Features/Transactions/List/TransactionListByDateView.swift"
gmv "$SRC/TransactionListByKindView.swift"              "$SRC/Features/Transactions/List/TransactionListByKindView.swift"
gmv "$SRC/TransactionListByMerchantView.swift"          "$SRC/Features/Transactions/List/TransactionListByMerchantView.swift"
gmv "$SRC/TransactionDetailView.swift"                  "$SRC/Features/Transactions/Detail/TransactionDetailView.swift"
gmv "$SRC/AddTransactionView.swift"                     "$SRC/Features/Transactions/Add/AddTransactionView.swift"

echo ""
echo "=== 15. Features/Expenses (legacy) ==="
gmv "$SRC/AddExpenseView.swift"                         "$SRC/Features/Expenses/AddExpenseView.swift"
gmv "$SRC/ExpenseDetailView.swift"                      "$SRC/Features/Expenses/ExpenseDetailView.swift"
gmv "$SRC/ExpenseRowView.swift"                         "$SRC/Features/Expenses/ExpenseRowView.swift"
gmv "$SRC/ExpenseListByCashFlowView.swift"              "$SRC/Features/Expenses/ExpenseListByCashFlowView.swift"
gmv "$SRC/ExpenseListByCategoryView.swift"              "$SRC/Features/Expenses/ExpenseListByCategoryView.swift"
gmv "$SRC/ExpenseListByDateView.swift"                  "$SRC/Features/Expenses/ExpenseListByDateView.swift"
gmv "$SRC/ExpenseListByMerchantView.swift"              "$SRC/Features/Expenses/ExpenseListByMerchantView.swift"

echo ""
echo "=== 16. Features/Accounts ==="
gmv "$SRC/AccountsView.swift"                           "$SRC/Features/Accounts/AccountsView.swift"
gmv "$SRC/AccountRowView.swift"                         "$SRC/Features/Accounts/AccountRowView.swift"
gmv "$SRC/AccountDetailView.swift"                      "$SRC/Features/Accounts/AccountDetailView.swift"
gmv "$SRC/AddAccountView.swift"                         "$SRC/Features/Accounts/AddAccountView.swift"

echo ""
echo "=== 17. Features/Categories ==="
gmv "$SRC/CategoriesView.swift"                         "$SRC/Features/Categories/CategoriesView.swift"
gmv "$SRC/CategoryDetailView.swift"                     "$SRC/Features/Categories/CategoryDetailView.swift"
gmv "$SRC/CategoryIconView.swift"                       "$SRC/Features/Categories/CategoryIconView.swift"
gmv "$SRC/CategoryAppearance.swift"                     "$SRC/Features/Categories/CategoryAppearance.swift"
gmv "$SRC/AddCategoryView.swift"                        "$SRC/Features/Categories/AddCategoryView.swift"
gmv "$SRC/AddCategorySheet.swift"                       "$SRC/Features/Categories/AddCategorySheet.swift"
gmv "$SRC/EmojiPickerSheet.swift"                       "$SRC/Features/Categories/EmojiPickerSheet.swift"
gmv "$SRC/ReassignCategoryView.swift"                   "$SRC/Features/Categories/ReassignCategoryView.swift"

echo ""
echo "=== 18. Features/Rules ==="
gmv "$SRC/RulesView.swift"                              "$SRC/Features/Rules/RulesView.swift"
gmv "$SRC/RuleDetailView.swift"                         "$SRC/Features/Rules/RuleDetailView.swift"
gmv "$SRC/AddRuleView.swift"                            "$SRC/Features/Rules/AddRuleView.swift"
gmv "$SRC/BuiltInRulesView.swift"                       "$SRC/Features/Rules/BuiltInRulesView.swift"

echo ""
echo "=== 19. Features/Tags ==="
gmv "$SRC/TagsManagementView.swift"                     "$SRC/Features/Tags/TagsManagementView.swift"

echo ""
echo "=== 20. Features/Analytics ==="
gmv "$SRC/AnalyticsView.swift"                          "$SRC/Features/Analytics/AnalyticsView.swift"
gmv "$SRC/AnalyticsSnapshot.swift"                      "$SRC/Features/Analytics/AnalyticsSnapshot.swift"
gmv "$SRC/AnalyticsCardView.swift"                      "$SRC/Features/Analytics/AnalyticsCardView.swift"
gmv "$SRC/InteractiveBarChartView.swift"                "$SRC/Features/Analytics/InteractiveBarChartView.swift"
gmv "$SRC/AnalyticsBreakdown.swift"                     "$SRC/Features/Analytics/Models/AnalyticsBreakdown.swift"
gmv "$SRC/AnalyticsMode.swift"                          "$SRC/Features/Analytics/Models/AnalyticsMode.swift"
gmv "$SRC/AnalyticsPeriod.swift"                        "$SRC/Features/Analytics/Models/AnalyticsPeriod.swift"
gmv "$SRC/AnalyticsScope.swift"                         "$SRC/Features/Analytics/Models/AnalyticsScope.swift"
gmv "$SRC/AnalyticsTimeScale.swift"                     "$SRC/Features/Analytics/Models/AnalyticsTimeScale.swift"
gmv "$SRC/AnalyticsViewMode.swift"                      "$SRC/Features/Analytics/Models/AnalyticsViewMode.swift"

echo ""
echo "=== 21. Features/Currencies ==="
gmv "$SRC/CurrencyDisplay.swift"                        "$SRC/Features/Currencies/CurrencyDisplay.swift"
gmv "$SRC/CurrencyPickerView.swift"                     "$SRC/Features/Currencies/CurrencyPickerView.swift"
gmv "$SRC/AddTrackedCurrencyView.swift"                 "$SRC/Features/Currencies/AddTrackedCurrencyView.swift"

echo ""
echo "=== 22. Features/Settings ==="
gmv "$SRC/SettingsView.swift"                           "$SRC/Features/Settings/SettingsView.swift"

echo ""
echo "=== 23. Shared ==="
gmv "$SRC/DateRangePickerView.swift"                    "$SRC/Shared/Components/DateRangePickerView.swift"
gmv "$SRC/MonthRangeCalendarView.swift"                 "$SRC/Shared/Components/MonthRangeCalendarView.swift"
gmv "$SRC/Color+Hex.swift"                              "$SRC/Shared/Extensions/Color+Hex.swift"

echo ""
echo "=== Готово ==="
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Это был dry-run. Перезапусти без --dry-run чтобы выполнить."
else
    echo "Файлы перенесены через git mv (история сохранена)."
    echo ""
    echo "Следующие шаги:"
    echo "  1. Открой Finances.xcodeproj в Xcode — он автоматически увидит новую структуру"
    echo "     благодаря PBXFileSystemSynchronizedRootGroup."
    echo "  2. Cmd+Shift+K (Clean Build Folder), затем Cmd+B."
    echo "  3. Прогони тесты: Cmd+U."
    echo "  4. Если всё ок — git status; git commit -m 'chore: restructure project layout'"
    echo ""
    echo "Если хочешь увидеть изменения: git status"
fi
