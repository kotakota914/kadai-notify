import SwiftUI
import KadaiCore

/// 通知ルールの一覧を編集する部品(全体設定・科目・課題の 3 か所で使い回す)
struct ReminderRulesEditor: View {
    @Binding var rules: [ReminderRule]

    var body: some View {
        // $rules: 配列の中身を直接書き換えられるようにした「つながり(Binding)」
        ForEach($rules) { $rule in
            ReminderRuleRow(rule: $rule)
        }
        .onDelete { rules.remove(atOffsets: $0) }

        if rules.isEmpty {
            Text("通知しない")
                .foregroundStyle(.secondary)
        }

        Menu {
            Button("◯日前の時刻に鳴らす") { rules.append(.daysBefore(1)) }
            Button("◯時間前に鳴らす") { rules.append(.hoursBefore(3)) }
        } label: {
            Label("ルールを追加", systemImage: "plus.circle")
        }
    }
}

/// ルール 1 つ分の編集行(左にスワイプで削除)
struct ReminderRuleRow: View {
    @Binding var rule: ReminderRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("種類", selection: $rule.kind) {
                Text("◯日前の時刻").tag(ReminderRule.Kind.daysBefore)
                Text("◯時間前").tag(ReminderRule.Kind.hoursBefore)
            }
            .pickerStyle(.segmented)

            switch rule.kind {
            case .daysBefore:
                Stepper(rule.amount == 0 ? "締め切り当日" : "\(rule.amount) 日前", value: $rule.amount, in: 0...30)
                DatePicker("時刻", selection: timeBinding(hour: $rule.hour, minute: $rule.minute),
                           displayedComponents: .hourAndMinute)
            case .hoursBefore:
                Stepper("\(rule.amount) 時間前", value: $rule.amount, in: 1...72)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: rule.kind) { _, kind in
            if kind == .hoursBefore && rule.amount < 1 { rule.amount = 3 }
        }
    }
}

/// 「時」と「分」の数字を、時刻を選ぶ部品(DatePicker)で編集できる形に変換する
func timeBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
    Binding(
        get: {
            Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue,
                                  second: 0, of: .now) ?? .now
        },
        set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour.wrappedValue = components.hour ?? 0
            minute.wrappedValue = components.minute ?? 0
        }
    )
}

/// 0:00 からの「分」(21:00 = 1260)を DatePicker で編集できる形に変換する
func timeBinding(minutesOfDay: Binding<Int>) -> Binding<Date> {
    Binding(
        get: {
            Calendar.current.date(bySettingHour: minutesOfDay.wrappedValue / 60,
                                  minute: minutesOfDay.wrappedValue % 60, second: 0, of: .now) ?? .now
        },
        set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            minutesOfDay.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    )
}
