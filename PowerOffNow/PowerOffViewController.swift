import UIKit

/// 启动即关机。正常情况下你只会看到一瞬间的「正在关机…」，随后设备断电。
/// 只有 helper 拿不到 root（例如不是用 TrollStore 安装）时，才会停在这里报错。
final class PowerOffViewController: UIViewController {

    private let device = DeviceController()
    private var didStart = false

    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = UIColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "正在关机…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.text = "关机命令没有生效。\n\n大多数情况是这个 App 没拿到 root 权限，\n请确认是用 TrollStore 安装的。\n\n临时办法：长按电源键关机。"
        label.textColor = UIColor(white: 0.7, alpha: 1)
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        view.addSubview(quitButton)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -20),

            detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            detailLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),

            quitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quitButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 28),
        ])

        spinner.startAnimating()
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true

        // 留一点时间让画面显示出来，再动手
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.triggerPowerOff()
        }
    }

    private func triggerPowerOff() {
        // helper 会阻塞到设备断电；放到后台队列，避免卡住主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.device.powerOff()
            // 能走到这里就说明没关机
            DispatchQueue.main.async {
                self?.showFailure()
            }
        }
    }

    private func showFailure() {
        spinner.stopAnimating()
        titleLabel.isHidden = true
        detailLabel.isHidden = false
        quitButton.isHidden = false
    }

    @objc private func onQuit() {
        exit(EXIT_SUCCESS)
    }
}
