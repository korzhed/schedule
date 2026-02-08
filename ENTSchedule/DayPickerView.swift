import SwiftUI

struct DayPickerView: View {
    let days: [Date]
    @Binding var selectedDate: Date

    var body: some View {
        PagingDayPickerView(days: days, selectedDate: $selectedDate)
            .frame(height: 56)
    }
}
