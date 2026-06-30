//
//  DeveloperToolsViewController.swift
//  PTrack
//
//  Created by Codex on 2026/7/1.
//

#if DEBUG
import UIKit

final class DeveloperToolsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case proAccess
    }

    private enum ProAccessOption: CaseIterable {
        case unlocked
        case locked

        var isProUser: Bool {
            switch self {
            case .unlocked:
                return true
            case .locked:
                return false
            }
        }

        var titleKey: AppTextKey {
            switch self {
            case .unlocked:
                return .debugProAccessUnlocked
            case .locked:
                return .debugProAccessLocked
            }
        }

        var iconName: String {
            switch self {
            case .unlocked:
                return "lock.open.fill"
            case .locked:
                return "lock.fill"
            }
        }
    }

    private let cellReuseIdentifier = "DeveloperToolCell"

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        registerObservers()
        updateLocalizedText()
    }

    private func configureViews() {
        view.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelf)
        )
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: AppLanguageStore.languageDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProSubscriptionDidChange),
            name: ProSubscriptionManager.didChangeNotification,
            object: nil
        )
    }

    private func updateLocalizedText() {
        title = AppLocalization.text(.developerTools)
        tableView.reloadData()
    }

    @objc private func handleLanguageDidChange() {
        updateLocalizedText()
    }

    @objc private func handleProSubscriptionDidChange() {
        tableView.reloadData()
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section.allCases[section] {
        case .proAccess:
            return ProAccessOption.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section.allCases[section] {
        case .proAccess:
            return AppLocalization.text(.debugProAccessSimulation)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath)
        switch Section.allCases[indexPath.section] {
        case .proAccess:
            let option = ProAccessOption.allCases[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = AppLocalization.text(option.titleKey)
            content.image = UIImage(systemName: option.iconName)
            content.imageProperties.tintColor = option.isProUser ? AppColors.movinnGreen : .secondaryLabel
            cell.contentConfiguration = content
            cell.accessoryType = ProSubscriptionManager.shared.isProUser == option.isProUser ? .checkmark : .none
            cell.tintColor = AppColors.movinnGreen
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section.allCases[indexPath.section] {
        case .proAccess:
            let option = ProAccessOption.allCases[indexPath.row]
            ProSubscriptionManager.shared.setDebugProAccessOverride(option.isProUser)
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
        }
    }
}
#endif
