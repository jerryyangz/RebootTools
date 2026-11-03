import UIKit

/// 唯一的一个界面：启动后立即注销主屏幕。
/// 正常情况下你在屏幕上只会看到一瞬间的「正在注销…」，随后 SpringBoard 重启。
/// 只有拿不到权限（例如不是用 TrollStore 安装）时，才会停在这里显示失败原因。
final class RespringViewController: UIViewController {

    private let device = DeviceController()
    private var didStart = false

    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "正在注销…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.text = "没有权限结束 SpringBoard。\n\n请用 TrollStore 安装本 App（需要 platform-application 权限）后重试。"
        label.textColor = UIColor(white: 0.7, alpha: 1)
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        view.addSubview(titleLabel)
        view.addSubview(detailLabel)
        view.addSubview(retryButton)
        view.addSubview(quitButton)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -20),

            detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            detailLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 28),

            quitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quitButton.topAnchor.constraint(equalTo: retryButton.bottomAnchor, constant: 8),
        ])

        spinner.startAnimating()
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        triggerRespring()
    }

    // MARK: - 核心

    private func triggerRespring() {
        if device.respring() {
            // SpringBoard 收到 SIGTERM 后会把本 App 一并结束；
            // 万一没被结束，1.2 秒后自己也退出，用户看到的就是桌面。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                exit(EXIT_SUCCESS)
            }
        } else {
            showFailure()
        }
    }

    private func showFailure() {
        spinner.stopAnimating()
        titleLabel.isHidden = true
        detailLabel.isHidden = false
        retryButton.isHidden = false
        quitButton.isHidden = false
    }

    @objc private func onRetry() {
        detailLabel.isHidden = true
        retryButton.isHidden = true
        quitButton.isHidden = true
        titleLabel.isHidden = false
        spinner.startAnimating()
        triggerRespring()
    }

    @objc private func onQuit() {
        exit(EXIT_SUCCESS)
    }
}
