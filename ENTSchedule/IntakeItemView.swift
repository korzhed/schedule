import SwiftUI

struct TodayIntakeItem: Identifiable {
    let id = UUID()
    let name: String
}

struct TodayIntakeItemView: View {
    let item: TodayIntakeItem
    let isCompleted: Bool
    let onToggleCompleted: (Bool) -> Void

    var body: some View {
        HStack {
            Text(item.name)
                .strikethrough(isCompleted, color: .gray)

            Spacer()

            Button(action: { onToggleCompleted(!isCompleted) }) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? .green : .gray)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .opacity(isCompleted ? 0.5 : 1)
            .padding()
        }
    }
}

struct TodayIntakeItemView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TodayIntakeItemView(
                item: TodayIntakeItem(name: "Take vitamins"),
                isCompleted: false,
                onToggleCompleted: { _ in }
            )

            TodayIntakeItemView(
                item: TodayIntakeItem(name: "Drink water"),
                isCompleted: true,
                onToggleCompleted: { _ in }
            )
        }
    }
}
