import SwiftUI
import UIKit

struct PagingDayPickerView: UIViewRepresentable {
    let days: [Date]
    @Binding var selectedDate: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 12

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear

        collectionView.decelerationRate = .fast
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator

        collectionView.register(DayCell.self, forCellWithReuseIdentifier: "DayCell")

        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        uiView.reloadData()

        if let index = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }) {
            let indexPath = IndexPath(item: index, section: 0)
            uiView.layoutIfNeeded()
            uiView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        }
    }

    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate {
        var parent: PagingDayPickerView
        private let calendar = Calendar.current

        init(_ parent: PagingDayPickerView) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.days.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let day = parent.days[indexPath.item]
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "DayCell", for: indexPath) as! DayCell

            let isSelected = calendar.isDate(day, inSameDayAs: parent.selectedDate)
            cell.configure(date: day, isSelected: isSelected, calendar: calendar)

            return cell
        }

        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            return CGSize(width: 44, height: collectionView.bounds.height * 0.9)
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            selectItem(at: indexPath, in: collectionView, animated: true)
        }

        private func selectItem(at indexPath: IndexPath, in collectionView: UICollectionView, animated: Bool) {
            let day = parent.days[indexPath.item]
            let normalized = calendar.startOfDay(for: day)

            if !calendar.isDate(normalized, inSameDayAs: parent.selectedDate) {
                parent.selectedDate = normalized
            }

            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
            collectionView.reloadData()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                snapToNearestCell(scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            snapToNearestCell(scrollView)
        }

        private func snapToNearestCell(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }

            let center = collectionView.bounds.midX + collectionView.contentOffset.x

            var minDistance = CGFloat.greatestFiniteMagnitude
            var indexPathToSelect: IndexPath?

            for cell in collectionView.visibleCells {
                let cellCenter = cell.frame.midX
                let distance = abs(cellCenter - center)
                if distance < minDistance,
                   let indexPath = collectionView.indexPath(for: cell) {
                    minDistance = distance
                    indexPathToSelect = indexPath
                }
            }

            if let indexPath = indexPathToSelect {
                selectItem(at: indexPath, in: collectionView, animated: true)
            }
        }
    }

    class DayCell: UICollectionViewCell {
        private let weekdayLabel = UILabel()
        private let dayLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)

            weekdayLabel.font = .systemFont(ofSize: 12, weight: .regular)
            weekdayLabel.textAlignment = .center

            dayLabel.font = .systemFont(ofSize: 17, weight: .semibold)
            dayLabel.textAlignment = .center

            let stack = UIStackView(arrangedSubviews: [weekdayLabel, dayLabel])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 4

            contentView.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])

            contentView.layer.cornerRadius = 22
            contentView.layer.masksToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(date: Date, isSelected: Bool, calendar: Calendar) {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "E"

            weekdayLabel.text = formatter.string(from: date)
            dayLabel.text = "\(calendar.component(.day, from: date))"

            let isToday = calendar.isDateInToday(date)

            if isSelected {
                // Стиль выбранного дня: белый фон, синий бордер и синий текст
                contentView.backgroundColor = UIColor.systemBackground
                contentView.layer.borderWidth = 1
                contentView.layer.borderColor = UIColor.systemBlue.cgColor
                weekdayLabel.textColor = .systemBlue
                dayLabel.textColor = .systemBlue
            } else {
                contentView.backgroundColor = UIColor.clear
                weekdayLabel.textColor = .secondaryLabel
                dayLabel.textColor = .label

                if isToday {
                    // Сегодня, но не выбрано: только синий контур
                    contentView.layer.borderWidth = 1
                    contentView.layer.borderColor = UIColor.systemBlue.cgColor
                } else {
                    contentView.layer.borderWidth = 0
                    contentView.layer.borderColor = nil
                }
            }
        }
    }
}
