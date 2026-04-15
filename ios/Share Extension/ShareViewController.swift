import UIKit

class ShareViewController: FSIShareViewController {

    // MARK: - UI
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Start collecting the shared attachments in the background.
        // onAttachmentsReady() will enable the send button when done.
        processAttachments()
    }

    // MARK: - FSIShareViewController hook
    override func onAttachmentsReady() {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.spinner.isHidden = true
            self.subtitleLabel.text = "Tap below to navigate to this destination."
            self.sendButton.isEnabled = true
            UIView.animate(withDuration: 0.2) { self.sendButton.alpha = 1 }
        }
    }

    // MARK: - Layout
    private func setupUI() {
        // Icon
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        let iconView = UIImageView(
            image: UIImage(systemName: "scooter", withConfiguration: iconConfig))
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.text = "Send to unu Scooter"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle / status
        subtitleLabel.text = "Preparing destination…"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Spinner
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        // Send button — disabled until attachments are ready
        var sendConfig = UIButton.Configuration.filled()
        sendConfig.title = "Send to Scooter"
        sendConfig.baseForegroundColor = .systemBackground
        sendConfig.baseBackgroundColor = .label
        sendConfig.cornerStyle = .large
        sendConfig.buttonSize = .large
        sendButton.configuration = sendConfig
        sendButton.isEnabled = false
        sendButton.alpha = 0.4
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        // Cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.secondaryLabel, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        [iconView, titleLabel, subtitleLabel, spinner, sendButton, cancelButton].forEach {
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 52),
            iconView.heightAnchor.constraint(equalToConstant: 52),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            spinner.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            sendButton.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 20),
            sendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            sendButton.heightAnchor.constraint(equalToConstant: 54),

            cancelButton.topAnchor.constraint(equalTo: sendButton.bottomAnchor, constant: 8),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions
    @objc private func sendTapped() {
        sendButton.isEnabled = false
        saveAndRedirect()
    }

    @objc private func cancelTapped() {
        completeAndExit()
    }
}
