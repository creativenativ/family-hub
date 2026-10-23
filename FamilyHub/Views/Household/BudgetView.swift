import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BudgetItem.name) private var allItems: [BudgetItem]
    @Query(sort: \BudgetExpense.date, order: .reverse) private var allExpenses: [BudgetExpense]
    @Query(sort: \IncomeSource.nextPayDate) private var incomes: [IncomeSource]
    @Query(sort: \RecurringBill.nextDueDate) private var bills: [RecurringBill]

    @State private var displayedMonth = Date().startOfMonth
    @State private var showingAddBudget = false
    @State private var showingAddIncome = false
    @State private var showingAddBill = false
    @State private var detailItem: BudgetItem?
    @State private var logItem: BudgetItem?
    @State private var editingIncome: IncomeSource?
    @State private var editingBill: RecurringBill?

    private var monthItems: [BudgetItem] {
        allItems.filter { $0.monthStart.isSameMonth(as: displayedMonth) }
    }

    private var totalPlanned: Double {
        monthItems.reduce(0) { $0 + $1.plannedAmount }
    }

    private var totalSpent: Double {
        monthItems.reduce(0) { $0 + $1.spentAmount }
    }

    private var currency: FloatingPointFormatStyle<Double>.Currency {
        .currency(code: Locale.current.currency?.identifier ?? "USD")
    }

    private var anchorIncome: IncomeSource? {
        incomes.first
    }

    private var payPeriod: (start: Date, end: Date)? {
        guard let anchor = anchorIncome else { return nil }
        return anchor.payPeriod()
    }

    private var periodIncomeTotal: Double {
        guard let period = payPeriod else { return 0 }
        let matched = incomes.reduce(0.0) { partial, income in
            let pay = income.nextPayDate.startOfDay
            if pay >= period.start && pay <= period.end {
                return partial + income.amount
            }
            return partial
        }
        if matched > 0 { return matched }
        return anchorIncome?.amount ?? 0
    }

    private var periodSpent: Double {
        guard let period = payPeriod else { return 0 }
        return allExpenses.reduce(0) { partial, expense in
            let day = expense.date.startOfDay
            if day >= period.start && day <= period.end {
                return partial + expense.amount
            }
            return partial
        }
    }

    private var periodBillsDue: Double {
        guard let period = payPeriod else { return 0 }
        return bills.reduce(0) { partial, bill in
            let due = bill.nextDueDate.startOfDay
            if due >= period.start && due <= period.end {
                return partial + bill.amount
            }
            return partial
        }
    }

    private var isEmpty: Bool {
        monthItems.isEmpty && incomes.isEmpty && bills.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                ContentUnavailableView {
                    Label("Money at a glance", systemImage: "dollarsign.circle")
                } description: {
                    Text("Add income and pay dates, recurring bills, and budget lines to track spending between paychecks.")
                } actions: {
                    Button("Add income") { showingAddIncome = true }
                    Button("Add bill") { showingAddBill = true }
                    Button("Add budget line") { showingAddBudget = true }
                }
            } else {
                List {
                    if let period = payPeriod, let anchor = anchorIncome {
                        Section {
                            payPeriodCard(period: period, anchor: anchor)
                        } header: {
                            Text("This pay period")
                        } footer: {
                            Text("Spent and bills use dates through payday. Income counts paychecks landing in this window.")
                        }
                    }

                    Section {
                        if incomes.isEmpty {
                            Button("Add income / payday") { showingAddIncome = true }
                        } else {
                            ForEach(incomes, id: \.id) { income in
                                Button {
                                    editingIncome = income
                                } label: {
                                    IncomeRow(income: income, currency: currency)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteIncomes)

                            Button {
                                showingAddIncome = true
                            } label: {
                                Label("Add income", systemImage: "plus")
                            }
                        }
                    } header: {
                        Text("Income")
                    }

                    Section {
                        if bills.isEmpty {
                            Button("Add recurring bill") { showingAddBill = true }
                        } else {
                            ForEach(bills, id: \.id) { bill in
                                Button {
                                    editingBill = bill
                                } label: {
                                    BillRow(bill: bill, currency: currency)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    Button("Paid") {
                                        markBillPaid(bill)
                                    }
                                    .tint(.green)
                                }
                            }
                            .onDelete(perform: deleteBills)

                            Button {
                                showingAddBill = true
                            } label: {
                                Label("Add bill", systemImage: "plus")
                            }
                        }
                    } header: {
                        Text("Recurring bills")
                    } footer: {
                        Text("Bills can appear on the calendar. Adjust reminder timing when you add or edit a bill. Swipe right to mark paid and roll to the next due date.")
                    }

                    if !monthItems.isEmpty {
                        Section {
                            monthBudgetSummary
                        } header: {
                            Text("Monthly budget · \(displayedMonth.formattedMonthYear())")
                        }

                        ForEach(BudgetCategoryKind.allCases) { category in
                            let items = monthItems.filter { $0.category == category }
                            if !items.isEmpty {
                                Section {
                                    ForEach(items, id: \.id) { item in
                                        BudgetItemRow(item: item, currency: currency) {
                                            detailItem = item
                                        } onLogExpense: {
                                            logItem = item
                                        }
                                    }
                                    .onDelete { offsets in
                                        deleteBudgetItems(items, at: offsets)
                                    }
                                } header: {
                                    Label(category.label, systemImage: category.icon)
                                }
                            }
                        }
                    } else {
                        Section {
                            Button("Add budget line") { showingAddBudget = true }
                        } header: {
                            Text("Monthly budget")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .safeAreaInset(edge: .top) {
            if !isEmpty {
                monthHeader
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Income", systemImage: "banknote") { showingAddIncome = true }
                    Button("Bill", systemImage: "doc.text") { showingAddBill = true }
                    Button("Budget line", systemImage: "chart.bar") { showingAddBudget = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddBudget) {
            AddBudgetItemView(monthStart: displayedMonth)
        }
        .sheet(isPresented: $showingAddIncome) {
            IncomeEditorView()
        }
        .sheet(item: $editingIncome) { income in
            IncomeEditorView(income: income)
        }
        .sheet(isPresented: $showingAddBill) {
            BillEditorView()
        }
        .sheet(item: $editingBill) { bill in
            BillEditorView(bill: bill)
        }
        .sheet(item: $logItem) { item in
            LogBudgetExpenseView(item: item)
        }
        .sheet(item: $detailItem) { item in
            BudgetItemDetailView(item: item)
        }
        .task {
            for bill in bills {
                bill.advanceDueDateIfNeeded()
                BillScheduleService.syncCalendarEvent(for: bill, in: modelContext)
            }
            for income in incomes {
                income.advancePayDateIfNeeded()
            }
            await BillScheduleService.rescheduleAll(for: bills)
        }
    }

    private func payPeriodCard(period: (start: Date, end: Date), anchor: IncomeSource) -> some View {
        let remaining = periodIncomeTotal - periodSpent
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(period.start.formatted()) – \(period.end.formatted())")
                .font(.subheadline.weight(.semibold))
            Text("Based on \(anchor.name) · \(anchor.frequency.label)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                summaryChip(title: "Pay", value: periodIncomeTotal, color: .secondary)
                summaryChip(title: "Spent", value: periodSpent, color: periodSpent > periodIncomeTotal ? .red : .primary)
                summaryChip(title: "Left", value: remaining, color: remaining < 0 ? .red : .green)
            }

            if periodBillsDue > 0 {
                HStack {
                    Text("Bills due this period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(periodBillsDue, format: currency)
                        .font(.caption.weight(.semibold))
                }
                Text("After bills & spending: \((remaining - periodBillsDue), format: currency)")
                    .font(.caption)
                    .foregroundStyle(remaining - periodBillsDue < 0 ? .red : .secondary)
            }

            ProgressView(
                value: min(periodSpent, max(periodIncomeTotal, 0.01)),
                total: max(periodIncomeTotal, 0.01)
            )
            .tint(periodSpent > periodIncomeTotal ? .red : .accentColor)
        }
        .padding(.vertical, 4)
    }

    private var monthBudgetSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                summaryChip(title: "Planned", value: totalPlanned, color: .secondary)
                summaryChip(title: "Spent", value: totalSpent, color: totalSpent > totalPlanned ? .red : .primary)
                summaryChip(title: "Left", value: totalPlanned - totalSpent, color: totalPlanned - totalSpent < 0 ? .red : .green)
            }
            ProgressView(value: min(totalSpent, totalPlanned), total: max(totalPlanned, 1))
                .tint(totalSpent > totalPlanned ? .red : .accentColor)
        }
        .padding(.vertical, 4)
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(displayedMonth.formattedMonthYear())
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func summaryChip(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: currency)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shiftMonth(by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth.startOfMonth
        }
    }

    private func deleteBudgetItems(_ items: [BudgetItem], at offsets: IndexSet) {
        for index in offsets { modelContext.delete(items[index]) }
    }

    private func deleteIncomes(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(incomes[index]) }
    }

    private func deleteBills(at offsets: IndexSet) {
        for index in offsets {
            let bill = bills[index]
            Task { await BillScheduleService.cancelReminder(for: bill.id) }
            BillScheduleService.removeCalendarEvent(for: bill, in: modelContext)
            modelContext.delete(bill)
        }
    }

    private func markBillPaid(_ bill: RecurringBill) {
        bill.markPaidAndAdvance()
        BillScheduleService.syncCalendarEvent(for: bill, in: modelContext)
        Task {
            if bill.remindersEnabled {
                _ = await BillScheduleService.requestPermission()
            }
            await BillScheduleService.scheduleReminder(for: bill)
        }
    }
}

struct IncomeRow: View {
    let income: IncomeSource
    let currency: FloatingPointFormatStyle<Double>.Currency

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(income.name)
                    .foregroundStyle(.primary)
                Text("\(income.frequency.label) · next \(income.nextPayDate.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(income.amount, format: currency)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 2)
    }
}

struct BillRow: View {
    let bill: RecurringBill
    let currency: FloatingPointFormatStyle<Double>.Currency

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("Due \(bill.nextDueDate.formatted())")
                    if bill.addToCalendar {
                        Image(systemName: "calendar")
                    }
                    if bill.remindersEnabled {
                        Image(systemName: "bell")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(bill.amount, format: currency)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Income editor

struct IncomeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var income: IncomeSource?

    @State private var name = ""
    @State private var amountText = ""
    @State private var frequency: MoneyFrequency = .biweekly
    @State private var nextPayDate = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Paycheck") {
                    TextField("Name (e.g. Payroll)", text: $name)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Frequency", selection: $frequency) {
                        ForEach(MoneyFrequency.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    DatePicker("Next pay date", selection: $nextPayDate, displayedComponents: .date)
                }
                Section("Notes") {
                    TextField("Optional", text: $notes)
                }
            }
            .navigationTitle(income == nil ? "Add Income" : "Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount == nil)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private var parsedAmount: Double? {
        let value = Double(amountText.replacingOccurrences(of: ",", with: "."))
        guard let value, value > 0 else { return nil }
        return value
    }

    private func load() {
        guard let income else { return }
        name = income.name
        amountText = income.amount > 0 ? String(income.amount) : ""
        frequency = income.frequency
        nextPayDate = income.nextPayDate
        notes = income.notes
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let income {
            income.name = trimmed
            income.amount = amount
            income.frequency = frequency
            income.nextPayDate = nextPayDate.startOfDay
            income.notes = notes
            income.advancePayDateIfNeeded()
        } else {
            let created = IncomeSource(
                name: trimmed,
                amount: amount,
                frequency: frequency,
                nextPayDate: nextPayDate,
                notes: notes
            )
            created.advancePayDateIfNeeded()
            modelContext.insert(created)
        }
        dismiss()
    }
}

// MARK: - Bill editor

struct BillEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var bill: RecurringBill?

    @State private var name = ""
    @State private var amountText = ""
    @State private var frequency: MoneyFrequency = .monthly
    @State private var nextDueDate = Date()
    @State private var category: BudgetCategoryKind = .utilities
    @State private var notes = ""
    @State private var addToCalendar = true
    @State private var remindersEnabled = true
    @State private var reminderLead: BillReminderLead = .threeDays

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name (e.g. Electric)", text: $name)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Category", selection: $category) {
                        ForEach(BudgetCategoryKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.icon).tag(kind)
                        }
                    }
                    Picker("Repeats", selection: $frequency) {
                        ForEach(MoneyFrequency.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    DatePicker("Next due date", selection: $nextDueDate, displayedComponents: .date)
                }

                Section("Calendar & reminders") {
                    Toggle("Show on calendar", isOn: $addToCalendar)
                    Toggle("Payment reminder", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Picker("Notify", selection: $reminderLead) {
                            ForEach(BillReminderLead.allCases) { lead in
                                Text(lead.label).tag(lead)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes)
                }
            }
            .navigationTitle(bill == nil ? "Add Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var parsedAmount: Double? {
        let value = Double(amountText.replacingOccurrences(of: ",", with: "."))
        guard let value, value > 0 else { return nil }
        return value
    }

    private func load() {
        guard let bill else { return }
        name = bill.name
        amountText = bill.amount > 0 ? String(bill.amount) : ""
        frequency = bill.frequency
        nextDueDate = bill.nextDueDate
        category = bill.category
        notes = bill.notes
        addToCalendar = bill.addToCalendar
        remindersEnabled = bill.remindersEnabled
        reminderLead = bill.reminderLead
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target: RecurringBill
        if let bill {
            bill.name = trimmed
            bill.amount = amount
            bill.frequency = frequency
            bill.nextDueDate = nextDueDate.startOfDay
            bill.category = category
            bill.notes = notes
            bill.addToCalendar = addToCalendar
            bill.remindersEnabled = remindersEnabled
            bill.reminderLead = reminderLead
            bill.advanceDueDateIfNeeded()
            target = bill
        } else {
            let created = RecurringBill(
                name: trimmed,
                amount: amount,
                frequency: frequency,
                nextDueDate: nextDueDate,
                category: category,
                notes: notes,
                addToCalendar: addToCalendar,
                remindersEnabled: remindersEnabled,
                reminderLead: reminderLead
            )
            created.advanceDueDateIfNeeded()
            modelContext.insert(created)
            target = created
        }

        BillScheduleService.syncCalendarEvent(for: target, in: modelContext)
        Task {
            if target.remindersEnabled {
                _ = await BillScheduleService.requestPermission()
            }
            await BillScheduleService.scheduleReminder(for: target)
        }
        dismiss()
    }
}

// MARK: - Existing budget item UI

struct BudgetItemRow: View {
    @Bindable var item: BudgetItem
    let currency: FloatingPointFormatStyle<Double>.Currency
    let onOpenDetail: () -> Void
    let onLogExpense: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpenDetail) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.spentAmount, format: currency)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.isOverBudget ? .red : .primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    ProgressView(value: min(item.spentAmount, item.plannedAmount), total: max(item.plannedAmount, 1))
                        .tint(item.isOverBudget ? .red : .accentColor)

                    HStack {
                        Text("Budget \(item.plannedAmount, format: currency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.isOverBudget ? "Over by \(abs(item.remaining), format: currency)" : "\(item.remaining, format: currency) left")
                            .font(.caption)
                            .foregroundStyle(item.isOverBudget ? .red : .secondary)
                    }

                    if !item.sortedExpenses.isEmpty {
                        Text("\(item.sortedExpenses.count) logged · tap for history")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onLogExpense) {
                Label("Log spending", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct LogBudgetExpenseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]

    @Bindable var item: BudgetItem

    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var paidByID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Details") {
                    TextField("What was this for? (optional)", text: $note)
                    if !members.isEmpty {
                        Picker("Paid by", selection: $paidByID) {
                            Text("Not set").tag(UUID?.none)
                            ForEach(members, id: \.id) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                        }
                    }
                }

                Section {
                    Text("Adds to \(item.name). Dates count toward this pay period’s spending.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Log Spending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(parsedAmount == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var parsedAmount: Double? {
        let value = Double(amountText.replacingOccurrences(of: ",", with: "."))
        guard let value, value > 0 else { return nil }
        return value
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let paidBy = members.first { $0.id == paidByID }
        let expense = BudgetExpense(
            amount: amount,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            budgetItem: item,
            paidBy: paidBy
        )
        modelContext.insert(expense)
        item.recalculateSpentAmount()
        dismiss()
    }
}

struct BudgetItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: BudgetItem
    @State private var showingLog = false

    private var currency: FloatingPointFormatStyle<Double>.Currency {
        .currency(code: Locale.current.currency?.identifier ?? "USD")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Spent")
                            Spacer()
                            Text(item.spentAmount, format: currency)
                                .foregroundStyle(item.isOverBudget ? .red : .primary)
                        }
                        HStack {
                            Text("Budget")
                            Spacer()
                            Text(item.plannedAmount, format: currency)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(item.spentAmount, item.plannedAmount), total: max(item.plannedAmount, 1))
                            .tint(item.isOverBudget ? .red : .accentColor)
                        Text(item.isOverBudget ? "Over by \(abs(item.remaining), format: currency)" : "\(item.remaining, format: currency) left")
                            .font(.caption)
                            .foregroundStyle(item.isOverBudget ? .red : .secondary)
                    }
                }

                Section("History") {
                    if item.sortedExpenses.isEmpty {
                        if item.spentAmount > 0 {
                            Text("Current total is \(item.spentAmount, format: currency) from earlier logging. New entries will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No spending logged yet.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(item.sortedExpenses, id: \.id) { expense in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(expense.amount, format: currency)
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                    Text(expense.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !expense.note.isEmpty {
                                    Text(expense.note)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let paidBy = expense.paidBy {
                                    Text("Paid by \(paidBy.name)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingLog = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingLog) {
                LogBudgetExpenseView(item: item)
            }
        }
    }

    private func deleteExpenses(at offsets: IndexSet) {
        let expenses = item.sortedExpenses
        var keptTotal = 0.0
        for (index, expense) in expenses.enumerated() {
            if offsets.contains(index) {
                modelContext.delete(expense)
            } else {
                keptTotal += expense.amount
            }
        }
        item.spentAmount = keptTotal
    }
}

struct AddBudgetItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let monthStart: Date

    @State private var name = ""
    @State private var plannedAmount = ""
    @State private var category: BudgetCategoryKind = .food
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Budget Line") {
                    TextField("Name", text: $name)
                    TextField("Planned amount", text: $plannedAmount)
                        .keyboardType(.decimalPad)
                    Picker("Category", selection: $category) {
                        ForEach(BudgetCategoryKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.icon).tag(kind)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Add Budget Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var parsedAmount: Double? {
        Double(plannedAmount.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let planned = parsedAmount else { return }
        let item = BudgetItem(
            name: name.trimmingCharacters(in: .whitespaces),
            plannedAmount: planned,
            category: category,
            monthStart: monthStart,
            notes: notes
        )
        modelContext.insert(item)
        dismiss()
    }
}
