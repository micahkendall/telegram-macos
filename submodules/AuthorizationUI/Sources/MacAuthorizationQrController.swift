#if targetEnvironment(macCatalyst)
import UIKit

final class MacAuthorizationQrController: UIViewController {
    private let imageView = UIImageView()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    var retry: (() -> Void)?
    var closed: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Log in with QR Code"
        self.preferredContentSize = CGSize(width: 420.0, height: 500.0)
        self.view.backgroundColor = .systemBackground
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closePressed))

        let instructions = UILabel()
        instructions.text = "Open Telegram on your phone. Go to Settings → Devices → Link Desktop Device and scan this code."
        instructions.numberOfLines = 0
        instructions.textAlignment = .center
        instructions.font = .preferredFont(forTextStyle: .body)

        self.imageView.contentMode = .scaleAspectFit
        self.imageView.backgroundColor = .white
        self.imageView.layer.magnificationFilter = .nearest
        self.imageView.isAccessibilityElement = true
        self.imageView.accessibilityLabel = "Telegram login QR code"
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.heightAnchor.constraint(equalToConstant: 240.0).isActive = true

        self.statusLabel.numberOfLines = 0
        self.statusLabel.textAlignment = .center
        self.statusLabel.font = .preferredFont(forTextStyle: .footnote)
        self.statusLabel.text = "Connecting…"
        self.retryButton.setTitle("Retry", for: .normal)
        self.retryButton.addTarget(self, action: #selector(self.retryPressed), for: .touchUpInside)
        self.retryButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [instructions, self.imageView, self.statusLabel, self.retryButton])
        stack.axis = .vertical
        stack.spacing = 20.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 340.0),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 24.0),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -24.0)
        ])
    }

    func update(image: UIImage?) {
        self.loadViewIfNeeded()
        self.imageView.image = image
        self.statusLabel.text = image == nil ? "Connecting…" : "Approve the login on your phone. This code refreshes automatically."
        self.retryButton.isHidden = true
    }

    func showError(rateLimited: Bool) {
        self.loadViewIfNeeded()
        self.imageView.image = nil
        self.statusLabel.text = rateLimited ? "Too many attempts. Wait before trying again." : "Could not load the login code. Check your connection and retry."
        self.retryButton.isHidden = rateLimited
    }

    @objc private func retryPressed() {
        self.update(image: nil)
        self.retry?()
    }

    @objc private func closePressed() {
        self.closed?()
        self.dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.navigationController?.isBeingDismissed == true {
            self.closed?()
        }
    }
}
#endif
