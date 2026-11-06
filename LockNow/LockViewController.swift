import UIKit

/// 唯一的一个界面：启动后立即请求锁屏。
/// 正常情况下只会看到一瞬间的「正在锁屏…」，随后屏幕熄灭。
/// 只有所有入口都没让系统锁屏时，才会停在这里显示诊断信息。
final class LockViewController: UIViewController {

    private let device = DeviceController()
    private var didStart = false
    private var attempt = 0

    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "正在锁屏…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "锁屏未生效"
        label.textColor = .white
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = "已向系统发送锁屏请求，但屏幕没有熄灭。\n请长按下方文字复制诊断信息发给开发者，或点重试再试一次。"
        label.textColor = UIColor(white: 0.72, alpha: 1)
        label.font = .systemFont(ofSize: 13)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let diagnosticsView: UITextView = {
        let view = UITextView()
        view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        view.textColor = UIColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 1)
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.isEditable = false
        view.isSelectable = true
        view.layer.cornerRadius = 10
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重试", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(onRetry), for: .touchUpInside)
        return button
    }()

    private lazy var quitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("退出", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(onQuit), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(spinner)
        view.addSubview(statusLabel)
        view.addSubview(titleLabel)
        view.addSubview(hintLabel)
        view.addSubview(diagnosticsView)
        view.addSubview(retryButton)
        view.addSubview(quitButton)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 20),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            diagnosticsView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 16),
            diagnosticsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            diagnosticsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            diagnosticsView.bottomAnchor.constraint(equalTo: retryButton.topAnchor, constant: -16),

            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryButton.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -8),
            quitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quitButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        spinner.startAnimating()
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        triggerLock()
    }

    // MARK: - 核心

    /// 锁屏请求放到后台队列，主线程保持空闲，确保锁屏成功后
    /// applicationDidEnterBackground 能及时触发并退出 App。
    private func triggerLock() {
        attempt += 1
        let currentAttempt = attempt
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = self.device.lockScreen()
            let log = self.device.diagnostics()
            DispatchQueue.main.async {
                // 锁屏成功时 App 已进后台并退出，这个回调不会有机会执行；
                // 仍在前台就说明锁屏请求没被系统接受。
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self else { return }
                    if UIApplication.shared.applicationState == .active {
                        self.showFailure(attempt: currentAttempt, log: log)
                    }
                }
            }
        }
    }

    private func showFailure(attempt: Int, log: String) {
        spinner.stopAnimating()
        statusLabel.isHidden = true
        titleLabel.isHidden = false
        hintLabel.isHidden = false
        diagnosticsView.isHidden = false
        diagnosticsView.text = "第 \(attempt) 次尝试\n\n" + log
        retryButton.isHidden = false
        quitButton.isHidden = false
    }

    @objc private func onRetry() {
        titleLabel.isHidden = true
        hintLabel.isHidden = true
        diagnosticsView.isHidden = true
        retryButton.isHidden = true
        quitButton.isHidden = true
        statusLabel.isHidden = false
        spinner.startAnimating()
        triggerLock()
    }

    @objc private func onQuit() {
        exit(EXIT_SUCCESS)
    }
}
