//
// MedicationsView.swift
// ENTSchedule
//

import SwiftUI

struct MedicationsView: View {

    @EnvironmentObject var appState: AppState

    @State private var medications: [MedicationItem] = []
    @State private var selectedMedication: MedicationItem? = nil

    let onComplete: ([MedicationItem]) -> Void

    init(initialMedications: [MedicationItem] = [], onComplete: @escaping ([MedicationItem]) -> Void) {
        _medications = State(initialValue: initialMedications)
        self.onComplete = onComplete
    }

    private var canContinue: Bool {
        !medications.isEmpty
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Шаг 2 из 3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Лекарства")
                        .font(.headline)
                    Text("Проверьте лекарства из назначения, при необходимости отредактируйте или добавьте новые.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if medications.isEmpty {
                    Text("Пока нет лекарств. Добавьте хотя бы одно, чтобы перейти дальше.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(medications) { med in
                        Button {
                            selectedMedication = med
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(med.name)
                                    .font(.headline)
                                Text("\(med.dosage), \(med.timesPerDay) раз(а) в день • \(med.durationInDays) дней")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let comment = med.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        medications.remove(atOffsets: indexSet)
                    }
                }
            }

            Section {
                Button {
                    addMockMedication()
                } label: {
                    Label("Добавить лекарство", systemImage: "plus.circle")
                }
            }

            if canContinue {
                Section {
                    Button {
                        onComplete(medications)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Перейти к расписанию")
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Лекарства")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMedication) { med in
            NavigationStack {
                if let index = medications.firstIndex(where: { $0.id == med.id }) {
                    MedicationDetailView(medication: $medications[index])
                } else {
                    Text("Не удалось найти лекарство")
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func addMockMedication() {
        let new = MedicationItem(
            id: UUID(),
            name: "Новое лекарство",
            dosage: "1 доза",
            timesPerDay: 1,
            durationInDays: 3,
            comment: ""
        )
        medications.append(new)
    }
}

struct MedicationsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MedicationsView(onComplete: { _ in })
                .environmentObject(AppState())
        }
    }
}
