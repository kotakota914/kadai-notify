import WidgetKit
import SwiftUI
import SwiftData
import KadaiCore

// ホーム画面ウィジェット。アプリと同じデータベース(App Group の共有フォルダ)を読んで表示するだけ。

/// ウィジェットに出す 1 件分(データベースから取り出した写し)
struct WidgetTask: Hashable {
    let subject: String
    let title: String
    let due: Date
    let colorHex: String
}

/// ある時刻に表示する内容
struct KadaiEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let pendingCount: Int

    static let sample = KadaiEntry(
        date: .now,
        tasks: [
            WidgetTask(subject: "情報システム", title: "第8回レポート", due: .now.addingTimeInterval(3 * 3600), colorHex: "#0090FF"),
            WidgetTask(subject: "論理回路", title: "演習課題5", due: .now.addingTimeInterval(30 * 3600), colorHex: "#30A46C"),
            WidgetTask(subject: "PD入門", title: "振り返りシート", due: .now.addingTimeInterval(80 * 3600), colorHex: "#E5484D"),
        ],
        pendingCount: 3)
}

/// いつ何を表示するかを iOS に渡す係
struct KadaiProvider: TimelineProvider {
    /// データベースは 1 回だけ開いて使い回す
    private static let container = SharedStore.makeContainer()

    func placeholder(in context: Context) -> KadaiEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (KadaiEntry) -> Void) {
        completion(context.isPreview ? .sample : load(now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KadaiEntry>) -> Void) {
        let now = Date()
        let current = load(now: now)
        // 残り時間の表示を進めるため、15 分ごとに 2 時間分の表示を用意しておく
        let entries = (0..<8).map { step in
            KadaiEntry(date: now.addingTimeInterval(Double(step) * 15 * 60),
                       tasks: current.tasks, pendingCount: current.pendingCount)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(2 * 3600))))
    }

    private func load(now: Date) -> KadaiEntry {
        guard let container = Self.container else {
            return KadaiEntry(date: now, tasks: [], pendingCount: 0)
        }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Assignment>(predicate: #Predicate { $0.isDone == false },
                                                     sortBy: [SortDescriptor(\.dueDate)])
        let pending = (try? context.fetch(descriptor)) ?? []
        let tasks = pending.prefix(3).map {
            WidgetTask(subject: $0.subject?.name ?? "", title: $0.title, due: $0.dueDate,
                       colorHex: $0.subject?.colorHex ?? "#999999")
        }
        return KadaiEntry(date: now, tasks: Array(tasks), pendingCount: pending.count)
    }
}

struct KadaiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KadaiEntry

    var body: some View {
        Group {
            if entry.tasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                    Text("提出物はありません")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if family == .systemSmall {
                hero(entry.tasks[0])
            } else {
                HStack(alignment: .top, spacing: 12) {
                    hero(entry.tasks[0])
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rest
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
    }

    /// 背景。いちばん近い提出物の状態で色を変える(期限切れ = 赤、今日 = オレンジ、それ以外 = 科目の色)
    static func background(for entry: KadaiEntry) -> some View {
        let base: Color
        if let task = entry.tasks.first {
            switch DueGroup.group(for: task.due, now: entry.date, calendar: .current) {
            case .overdue: base = Color(hex: "#E5484D")
            case .today: base = Color(hex: "#F76B15")
            default: base = Color(hex: task.colorHex)
            }
        } else {
            base = Color(hex: "#30A46C")
        }
        return WidgetBackdrop(base: base, symbol: "bell.fill")
    }

    /// いちばん近い 1 件を大きく見せる
    private func hero(_ task: WidgetTask) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("次の締め切り", systemImage: "bell.fill")
                .font(.caption2.weight(.semibold))
                .opacity(0.85)
            Spacer(minLength: 4)
            Text(DeadlineText.remaining(until: task.due, now: entry.date))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 4)
            Text(task.title)
                .font(.subheadline.bold())
                .lineLimit(2)
            Text(task.subject.isEmpty ? "未完了 \(entry.pendingCount) 件" : "\(task.subject) ・ 未完了 \(entry.pendingCount) 件")
                .font(.caption2)
                .opacity(0.8)
                .lineLimit(1)
        }
    }

    /// 中サイズの右側: 2 件目・3 件目
    private var rest: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("このあと")
                .font(.caption2.weight(.semibold))
                .opacity(0.85)
            if entry.tasks.count < 2 {
                Text("ほかの提出物はありません")
                    .font(.caption2)
                    .opacity(0.8)
            }
            ForEach(Array(entry.tasks.dropFirst().enumerated()), id: \.offset) { _, task in
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text("\(DeadlineText.remaining(until: task.due, now: entry.date)) ・ \(task.subject)")
                        .font(.caption2)
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
    }
}

/// ウィジェットの背景。色のグラデーションの上に、大きなうすい絵を右下に置く
struct WidgetBackdrop: View {
    let base: Color
    let symbol: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [base.mix(with: .white, by: 0.12), base.mix(with: .black, by: 0.38)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.system(size: 84))
                .foregroundStyle(.white.opacity(0.10))
                .rotationEffect(.degrees(-12))
                .offset(x: 14, y: 16)
        }
    }
}

struct KadaiWidget: Widget {
    let kind = "KadaiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KadaiProvider()) { entry in
            KadaiWidgetView(entry: entry)
                .containerBackground(for: .widget) { KadaiWidgetView.background(for: entry) }
        }
        .configurationDisplayName("次の締め切り")
        .description("締め切りが近い提出物を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - テストまでの日数のウィジェット

/// ウィジェットに出すテスト 1 件分
struct WidgetExam: Hashable {
    let subject: String
    let title: String
    let date: Date
    let colorHex: String
}

struct ExamEntry: TimelineEntry {
    let date: Date
    let exams: [WidgetExam]

    static let sample = ExamEntry(
        date: .now,
        exams: [
            WidgetExam(subject: "論理回路", title: "小テスト 3", date: .now.addingTimeInterval(2 * 86400), colorHex: "#30A46C"),
            WidgetExam(subject: "情報システム", title: "期末試験", date: .now.addingTimeInterval(12 * 86400), colorHex: "#0090FF"),
        ])
}

struct ExamProvider: TimelineProvider {
    private static let container = SharedStore.makeContainer()

    func placeholder(in context: Context) -> ExamEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ExamEntry) -> Void) {
        completion(context.isPreview ? .sample : ExamEntry(date: .now, exams: load(now: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExamEntry>) -> Void) {
        let now = Date()
        let exams = load(now: now)
        // 残り日数は日付が変わると減るので、1 時間ごとに 6 時間分の表示を用意しておく
        let entries = (0..<6).map { step in
            ExamEntry(date: now.addingTimeInterval(Double(step) * 3600), exams: exams)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    /// これから来るテストを、近い順に 3 件まで
    private func load(now: Date) -> [WidgetExam] {
        guard let container = Self.container else { return [] }
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<Exam>(sortBy: [SortDescriptor(\.date)]))) ?? []
        return all.filter { $0.date > now }.prefix(3).map {
            WidgetExam(subject: $0.subject?.name ?? "", title: $0.title, date: $0.date,
                       colorHex: $0.subject?.colorHex ?? "#999999")
        }
    }
}

struct ExamWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ExamEntry

    /// 表示の時刻より後のテストだけ(用意しておいた表示の途中でテストが終わることがあるため)
    static func upcoming(_ entry: ExamEntry) -> [WidgetExam] {
        entry.exams.filter { $0.date > entry.date }
    }

    var body: some View {
        let exams = Self.upcoming(entry)
        Group {
            if exams.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .font(.largeTitle)
                    Text("テストの予定はありません")
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if family == .systemSmall {
                hero(exams[0])
            } else {
                HStack(alignment: .top, spacing: 12) {
                    hero(exams[0])
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rest(Array(exams.dropFirst()))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
    }

    /// 背景。次のテストが近いほど強い色にする(前日・当日 = 赤、3 日以内 = オレンジ、それ以外 = 科目の色)
    static func background(for entry: ExamEntry) -> some View {
        let base: Color
        if let exam = upcoming(entry).first {
            switch ExamCountdown.daysLeft(until: exam.date, now: entry.date, calendar: .current) {
            case ...1: base = Color(hex: "#E5484D")
            case 2...3: base = Color(hex: "#F76B15")
            default: base = Color(hex: exam.colorHex)
            }
        } else {
            base = Color(hex: "#6E56CF")
        }
        return WidgetBackdrop(base: base, symbol: "graduationcap.fill")
    }

    private func daysLeft(_ exam: WidgetExam) -> Int {
        ExamCountdown.daysLeft(until: exam.date, now: entry.date, calendar: .current)
    }

    /// 次のテスト 1 件。残り日数をいちばん大きく見せる
    private func hero(_ exam: WidgetExam) -> some View {
        let days = daysLeft(exam)
        return VStack(alignment: .leading, spacing: 0) {
            Label("テストまで", systemImage: "graduationcap.fill")
                .font(.caption2.weight(.semibold))
                .opacity(0.85)
            Spacer(minLength: 2)
            if days >= 2 {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("あと")
                        .font(.caption.weight(.semibold))
                        .opacity(0.85)
                    Text("\(days)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .widgetAccentable()
                    Text("日")
                        .font(.headline)
                        .opacity(0.85)
                }
            } else {
                Text(days == 1 ? "明日" : "今日")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .widgetAccentable()
            }
            Spacer(minLength: 2)
            Text(exam.title)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text(exam.subject.isEmpty ? DeadlineText.dateTime(exam.date, calendar: .current)
                                      : "\(exam.subject) ・ \(DeadlineText.dateTime(exam.date, calendar: .current))")
                .font(.caption2)
                .opacity(0.8)
                .lineLimit(1)
        }
    }

    /// 中サイズの右側: 2 件目・3 件目
    private func rest(_ exams: [WidgetExam]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("このあと")
                .font(.caption2.weight(.semibold))
                .opacity(0.85)
            if exams.isEmpty {
                Text("ほかのテストはありません")
                    .font(.caption2)
                    .opacity(0.8)
            }
            ForEach(Array(exams.enumerated()), id: \.offset) { _, exam in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exam.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Text(exam.subject.isEmpty ? DeadlineText.date(exam.date, calendar: .current) : exam.subject)
                            .font(.caption2)
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Text(ExamCountdown.text(until: exam.date, now: entry.date, calendar: .current))
                        .font(.caption.weight(.heavy))
                        .lineLimit(1)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
    }
}

struct ExamWidget: Widget {
    let kind = "ExamWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExamProvider()) { entry in
            ExamWidgetView(entry: entry)
                .containerBackground(for: .widget) { ExamWidgetView.background(for: entry) }
        }
        .configurationDisplayName("テストまでの日数")
        .description("次のテストまで、あと何日かを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct KadaiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KadaiWidget()
        ExamWidget()
    }
}

#Preview(as: .systemMedium) {
    KadaiWidget()
} timeline: {
    KadaiEntry.sample
}
