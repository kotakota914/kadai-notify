import SwiftUI
import SwiftData
import KadaiCore

/// 「カレンダー」タブ。月のカレンダーで、締め切りのある日を見る
struct CalendarTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var editing: Assignment?

    var body: some View {
        NavigationStack {
            // 1 分ごとに描き直す(「今日」の位置や残り時間がずれないように)
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                MonthCalendarView(assignments: assignments, now: timeline.date,
                                  onEdit: { editing = $0 },
                                  onToggle: { AssignmentActions.toggleDone($0, in: context) })
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { assignment in AssignmentEditView(assignment: assignment) }
        }
    }
}

/// 「ガント」タブ。科目ごとに、未完了の提出物の期間を横棒の図(ガントチャート)で見る。
/// 提出物がない科目も並べるので、「いま課題がある科目・ない科目」がひと目で分かる
struct GanttTabView: View {
    @Query(sort: \Subject.name) private var subjects: [Subject]
    // 未完了だけを、締め切りが近い順に取り出す
    @Query(filter: #Predicate<Assignment> { $0.isDone == false }, sort: \Assignment.dueDate)
    private var pending: [Assignment]
    @State private var editing: Assignment?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                GanttChartView(subjects: subjects, assignments: pending, now: timeline.date,
                               onEdit: { editing = $0 })
            }
            .navigationTitle("ガントチャート")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { assignment in AssignmentEditView(assignment: assignment) }
        }
    }
}

// MARK: - 月のカレンダー

/// 月のカレンダー。締め切りがある日に科目の色の点が付き、日を押すとその日の提出物が下に出る
struct MonthCalendarView: View {
    let assignments: [Assignment]
    let now: Date
    let onEdit: (Assignment) -> Void
    let onToggle: (Assignment) -> Void

    private let calendar = Calendar.current
    /// 表示している月(その月の 1 日)
    @State private var month: Date = MonthGrid.firstOfMonth(.now, calendar: .current)
    /// 選んでいる日(その日の 0:00)
    @State private var selected: Date = Calendar.current.startOfDay(for: .now)

    /// 締め切りの日(0:00)ごとにまとめた提出物
    private var byDay: [Date: [Assignment]] {
        Dictionary(grouping: assignments) { calendar.startOfDay(for: $0.dueDate) }
    }

    var body: some View {
        let byDay = byDay
        List {
            Section {
                VStack(spacing: 6) {
                    monthHeader
                    weekdayHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                        ForEach(MonthGrid.days(inMonthOf: month, calendar: calendar), id: \.self) { day in
                            dayCell(day, items: byDay[day] ?? [])
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                let items = byDay[selected] ?? []
                if items.isEmpty {
                    Text("この日が締め切りの提出物はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { assignment in
                        AssignmentRow(assignment: assignment, now: now) { onToggle(assignment) }
                            .contentShape(Rectangle())
                            .onTapGesture { onEdit(assignment) }
                            .contextMenu {
                                Button { onEdit(assignment) } label: { Label("編集", systemImage: "pencil") }
                            } preview: {
                                AssignmentPeekView(assignment: assignment, now: now)
                            }
                    }
                }
            } header: {
                Text("\(DeadlineText.date(selected, calendar: calendar)) の提出物")
            }
        }
    }

    /// 「‹ 2026年11月 ›」と「今日」ボタン
    private var monthHeader: some View {
        HStack {
            Button { month = MonthGrid.addingMonths(-1, to: month, calendar: calendar) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 32)
            }
            .accessibilityLabel("前の月")
            Spacer()
            Text(MonthGrid.title(month, calendar: calendar))
                .font(.headline)
            Spacer()
            Button("今日") {
                month = MonthGrid.firstOfMonth(now, calendar: calendar)
                selected = calendar.startOfDay(for: now)
            }
            .font(.subheadline)
            Button { month = MonthGrid.addingMonths(1, to: month, calendar: calendar) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 32)
            }
            .accessibilityLabel("次の月")
        }
        // リストの行の中にボタンが複数あるとき、押した所だけが反応するようにする
        .buttonStyle(.borderless)
    }

    /// 「日 月 火 水 木 金 土」の見出し(日曜は赤、土曜は青)
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let weekday = (calendar.firstWeekday - 1 + index) % 7 + 1   // 1 = 日曜 … 7 = 土曜
                Text(DeadlineText.weekdaySymbol(weekday))
                    .font(.caption2)
                    .foregroundStyle(weekday == 1 ? Color.red : (weekday == 7 ? Color.blue : Color.secondary))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 1 日分のマス
    private func dayCell(_ day: Date, items: [Assignment]) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let numberColor: Color = isSelected ? .white
            : (!inMonth ? Color.secondary.opacity(0.5) : (isToday ? Color.accentColor : Color.primary))

        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(numberColor)
                .frame(width: 30, height: 30)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().stroke(Color.accentColor, lineWidth: 1)
                    }
                }
            // 締め切りがある日は、科目の色の点を最大 3 つ。それより多ければ「+」
            HStack(spacing: 2) {
                ForEach(items.prefix(3)) { assignment in
                    Circle()
                        .fill(assignment.isDone ? Color.secondary.opacity(0.4)
                                                : Color(hex: assignment.subject?.colorHex ?? "#999999"))
                        .frame(width: 5, height: 5)
                }
                if items.count > 3 {
                    Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            selected = day
            // 前後の月の日を押したら、その月へ移る
            if !inMonth { month = MonthGrid.firstOfMonth(day, calendar: calendar) }
        }
        .accessibilityLabel("\(DeadlineText.date(day, calendar: calendar))、提出物 \(items.count) 件")
    }
}

// MARK: - ガントチャート

/// ガントチャート。科目ごとに見出しの行を置き、その下に未完了の提出物を 1 行ずつ並べて、
/// 「登録した日 → 締め切り」を横棒で表す。提出物がない科目も見出しだけ出す
struct GanttChartView: View {
    let subjects: [Subject]
    /// 未完了の提出物(締め切りが近い順)
    let assignments: [Assignment]
    let now: Date
    let onEdit: (Assignment) -> Void

    private let calendar = Calendar.current
    private let dayWidth: CGFloat = 22        // 1 日分の横幅
    private let rowHeight: CGFloat = 40       // 提出物 1 行の高さ
    private let subjectHeight: CGFloat = 30   // 科目の見出しの行の高さ
    private let headerHeight: CGFloat = 40    // 日付の見出しの高さ
    private let labelWidth: CGFloat = 132     // 左の名前の列の幅

    /// 科目 1 つ分のまとまり(科目の見出し + その科目の未完了の提出物)
    private struct SubjectGroup: Identifiable {
        let id: String
        let subject: Subject?
        let items: [Assignment]
    }

    /// 科目ごとにまとめる。課題がある科目を締め切りが近い順に上へ、ない科目は名前順で下へ並べる
    private var groups: [SubjectGroup] {
        var result = subjects.map { subject in
            SubjectGroup(id: subject.uid.uuidString, subject: subject,
                         items: assignments.filter { $0.subject?.uid == subject.uid })
        }
        let withoutSubject = assignments.filter { $0.subject == nil }
        if !withoutSubject.isEmpty {
            result.append(SubjectGroup(id: "none", subject: nil, items: withoutSubject))
        }
        return result.sorted { a, b in
            switch (a.items.first?.dueDate, b.items.first?.dueDate) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (a.subject?.name ?? "") < (b.subject?.name ?? "")
            }
        }
    }

    /// 表示範囲の左端(今日の 3 日前の 0:00)
    private var rangeStart: Date {
        calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: now)) ?? now
    }

    var body: some View {
        let groups = groups
        if groups.isEmpty {
            ContentUnavailableView("科目がまだありません", systemImage: "chart.bar.xaxis",
                                   description: Text("提出物か科目を登録すると、ここに並びます。"))
        } else {
            let rangeStart = rangeStart
            let rangeDays = GanttLayout.rangeDays(latestDue: assignments.map(\.dueDate).max(), rangeStart: rangeStart)
            let days = (0..<rangeDays).compactMap { calendar.date(byAdding: .day, value: $0, to: rangeStart) }
            let totalHeight = CGFloat(groups.count) * subjectHeight + CGFloat(assignments.count) * rowHeight

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 0) {
                        labelColumn(groups)
                        Divider()
                        // 棒の部分だけ横にスクロールする(名前の列は動かない)
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                dateHeader(days)
                                ZStack(alignment: .topLeading) {
                                    weekendStripes(days, height: totalHeight)
                                    bars(groups, rangeStart: rangeStart, rangeDays: rangeDays)
                                    todayLine(rangeStart: rangeStart, height: totalHeight)
                                }
                            }
                            .frame(width: CGFloat(rangeDays) * dayWidth, alignment: .leading)
                        }
                    }
                    Text("科目ごとに、未完了の提出物を並べています。棒は着手日(決めていなければ登録した日)から締め切りまで、赤い縦線が今です。行を押すと編集できます。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func color(of subject: Subject?) -> Color {
        Color(hex: subject?.colorHex ?? "#999999")
    }

    /// 左の列: 科目の見出しと、その下の提出物の名前
    private func labelColumn(_ groups: [SubjectGroup]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: headerHeight)
            ForEach(groups) { group in
                // 科目の見出し: 色の印・科目名・件数(なければ「なし」)
                HStack(spacing: 5) {
                    Circle().fill(color(of: group.subject)).frame(width: 8, height: 8)
                    Text(group.subject?.name ?? "科目なし")
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(group.items.isEmpty ? "なし" : "\(group.items.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(width: labelWidth, height: subjectHeight, alignment: .leading)
                .background(color(of: group.subject).opacity(0.14))
                .opacity(group.items.isEmpty ? 0.6 : 1)

                ForEach(group.items) { assignment in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(assignment.title)
                            .font(.caption)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let rank = assignment.rank { RankBadge(rank: rank) }
                            Text(assignment.kind.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 22)
                    .padding(.trailing, 4)
                    .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(assignment) }
                }
            }
        }
        .frame(width: labelWidth)
    }

    /// 上の見出し: 月(1 日と左端だけ)と日
    private func dateHeader(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
                let isToday = calendar.isDate(day, inSameDayAs: now)
                VStack(spacing: 2) {
                    // 月の名前は幅からはみ出してよい(次の日のマスに重なって見える)
                    Text(index == 0 || parts.day == 1 ? "\(parts.month ?? 0)月" : " ")
                        .font(.caption2.bold())
                        .fixedSize()
                        .frame(width: dayWidth, alignment: .leading)
                    Text("\(parts.day ?? 0)")
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.red
                                         : (parts.weekday == 1 ? Color.red.opacity(0.7)
                                            : (parts.weekday == 7 ? Color.blue.opacity(0.8) : Color.secondary)))
                        .frame(width: dayWidth)
                }
                .frame(width: dayWidth, height: headerHeight)
            }
        }
    }

    /// 土日の列をうすく塗る
    private func weekendStripes(_ days: [Date], height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let weekday = calendar.component(.weekday, from: day)
                Rectangle()
                    .fill(weekday == 1 || weekday == 7 ? Color.secondary.opacity(0.08) : Color.clear)
                    .frame(width: dayWidth)
            }
        }
        .frame(height: height)
    }

    /// 科目の見出しの帯と、提出物ごとの横棒
    private func bars(_ groups: [SubjectGroup], rangeStart: Date, rangeDays: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                // 科目の見出しの帯。提出物がない科目は、ここに「未完了の提出物なし」と出す
                ZStack(alignment: .leading) {
                    Rectangle().fill(color(of: group.subject).opacity(0.14))
                    if group.items.isEmpty {
                        Text("未完了の提出物なし")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: 3.5 * dayWidth)   // 「今」の線の少し右
                    }
                }
                .frame(height: subjectHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(group.items) { assignment in
                    barRow(assignment, rangeStart: rangeStart, rangeDays: rangeDays)
                }
            }
        }
    }

    /// 提出物 1 件分の横棒
    private func barRow(_ assignment: Assignment, rangeStart: Date, rangeDays: Int) -> some View {
        let overdue = assignment.dueDate <= now
        let barColor = overdue ? Color.red : color(of: assignment.subject)
        return ZStack(alignment: .leading) {
            // 棒の始まり: 着手日を決めていればその日、決めていなければ登録した日
            if let bar = GanttLayout.bar(start: assignment.startDate ?? assignment.createdAt, end: assignment.dueDate,
                                         rangeStart: rangeStart, rangeDays: rangeDays) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(barColor.opacity(0.85))
                    .frame(width: max(CGFloat(bar.lengthDays) * dayWidth, 4), height: 16)
                    .offset(x: CGFloat(bar.offsetDays) * dayWidth)
                // 締め切りの日時を棒の右に書く
                Text(DeadlineText.dateTime(assignment.dueDate, calendar: calendar))
                    .font(.caption2)
                    .foregroundStyle(overdue ? Color.red : Color.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(bar.offsetDays + bar.lengthDays) * dayWidth + 4)
            } else {
                // 表示範囲より前に締め切りが過ぎたもの
                Text("◀ \(DeadlineText.dateTime(assignment.dueDate, calendar: calendar)) 期限切れ")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize()
                    .offset(x: 4)
            }
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(assignment) }
    }

    /// 「今」を表す赤い縦線
    private func todayLine(rangeStart: Date, height: CGFloat) -> some View {
        let offsetDays = now.timeIntervalSince(rangeStart) / (24 * 3600)
        return Rectangle()
            .fill(Color.red)
            .frame(width: 1.5, height: height)
            .offset(x: CGFloat(offsetDays) * dayWidth)
    }
}

#Preview("カレンダー") {
    CalendarTabView()
        .modelContainer(PreviewData.container)
}

#Preview("ガント") {
    GanttTabView()
        .modelContainer(PreviewData.container)
}
