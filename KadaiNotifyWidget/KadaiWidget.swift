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
        if entry.tasks.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("提出物はありません")
                    .font(.caption)
            }
        } else if family == .systemSmall {
            small
        } else {
            medium
        }
    }

    /// 小サイズ: 次の締め切り 1 件
    private var small: some View {
        let task = entry.tasks[0]
        return VStack(alignment: .leading, spacing: 4) {
            Text("次の締め切り")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Circle().fill(Color(hex: task.colorHex)).frame(width: 6, height: 6)
                Text(task.subject).font(.caption2).lineLimit(1)
            }
            Text(task.title)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(DeadlineText.remaining(until: task.due, now: entry.date))
                .font(.subheadline.bold())
                .foregroundStyle(color(for: task))
            Text("未完了 \(entry.pendingCount) 件")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 中サイズ: 締め切りが近い順に 3 件
    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("提出物")
                    .font(.caption.bold())
                Spacer()
                Text("未完了 \(entry.pendingCount) 件")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entry.tasks.enumerated()), id: \.offset) { _, task in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: task.colorHex))
                        .frame(width: 4, height: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(task.title).font(.subheadline).lineLimit(1)
                        Text("\(task.subject) ・ \(DeadlineText.relativeDay(task.due, now: entry.date, calendar: .current))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(DeadlineText.remaining(until: task.due, now: entry.date))
                        .font(.caption.bold())
                        .foregroundStyle(color(for: task))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for task: WidgetTask) -> Color {
        DueGroup.group(for: task.due, now: entry.date, calendar: .current).color
    }
}

struct KadaiWidget: Widget {
    let kind = "KadaiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KadaiProvider()) { entry in
            KadaiWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("次の締め切り")
        .description("締め切りが近い提出物を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct KadaiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KadaiWidget()
    }
}

#Preview(as: .systemMedium) {
    KadaiWidget()
} timeline: {
    KadaiEntry.sample
}
