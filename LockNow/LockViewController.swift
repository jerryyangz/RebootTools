import UIKit

/// 与真机验证成功的 RespringNow 保持同构：
/// 只用 UILabel / UIButton、简单约束、viewDidAppear 触发、主线程同步执行、绝不自动退出。
final class LockViewController: UIViewController {

    private let device = DeviceController()
    private var didStart = false

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "正在锁屏…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor(white: 0.78, alpha: 1)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textAlignment = .left
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("复制诊断", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(onCopy), for: .touchUpInside)
        return button
    }()

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重试", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(onRetry), for: .touchUpInside)
        return button
    }()

    private lazy var quitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("退出", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(onQuit), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(titleLabel)
        view.addSubview(detailLabel)
        view.addSubview(copyButton)
        view.addSubview(retryButton)
        view.addSubview(quitButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),
            detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: retryButton.topAnchor, constant: -16),

            copyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            copyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            quitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            quitButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        triggerLock()
    }

    // MARK: - 核心

    private func triggerLock() {
        titleLabel.text = "正在锁屏…"
        detailLabel.text = ""
        _ = device.lockScreen()
        showResult()
    }

    private func showResult() {
        titleLabel.text = device.isLocked() ? "已锁定 ✓ 屏幕应已熄灭" : "锁屏请求已发送"
        // 直接赋给 UILabel.text（String?），无论桥接成 String 还是 String? 都能编译
        detailLabel.text = device.diagnostics()
    }

    @objc private func onCopy() {
        UIPasteboard.general.string = detailLabel.text
        titleLabel.text = "诊断已复制 ✓"
    }

    @objc private func onRetry() {
        triggerLock()
    }

    @objc private func onQuit() {
        exit(EXIT_SUCCESS)
    }
}
