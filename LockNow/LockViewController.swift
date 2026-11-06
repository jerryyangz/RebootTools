import UIKit

/// 启动后自动请求锁屏，但**绝不自动退出**。
/// 上一次运行若发生过崩溃，会进入安全模式：先显示崩溃记录，由用户决定是否再试，
/// 避免「每次点开都闪退、连诊断都看不到」。
final class LockViewController: UIViewController {

    private let device = DeviceController()
    private var attempt = 0
    private var lastCrash: String = ""

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "正在锁屏…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 21, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
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
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重试", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(onAction), for: .touchUpInside)
        return button
    }()

    private lazy var quitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("退出", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(onQuit), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.06, alpha: 1)

        view.addSubview(titleLabel)
        view.addSubview(diagnosticsView)
        view.addSubview(actionButton)
        view.addSubview(quitButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            diagnosticsView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            diagnosticsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            diagnosticsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            diagnosticsView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -14),

            actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionButton.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -8),
            quitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quitButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        if let crash = LNLastCrashReport(), !crash.isEmpty {
            // 安全模式：上次崩过，这次不自动执行，先把证据给用户看。
            lastCrash = crash
            titleLabel.text = "上次运行发生崩溃 · 安全模式"
            diagnosticsView.text = "【崩溃记录】\n" + crash
                + "\n\n为避免连续闪退，本次启动没有自动锁屏。\n"
                + "请长按复制上面的内容发给开发者，或点下方按钮再试一次。"
            actionButton.setTitle("仍然尝试锁屏", for: .normal)
        } else {
            diagnosticsView.text = "正在向系统发送锁屏请求…"
            // 稍作延迟，确保 window 已可见，也避开 viewDidLoad 阶段的时序问题。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.triggerLock()
            }
        }
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - 核心

    private func triggerLock() {
        attempt += 1
        let n = attempt
        titleLabel.text = "正在锁屏…（第 \(n) 次）"
        diagnosticsView.text = "请稍候，正在逐条发送并读取系统状态…"
        actionButton.isEnabled = false

        // 通知发送与状态读取放在后台队列，主线程不阻塞（避免被 watchdog 杀掉）。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = self.device.lockScreen()
            let log: String = self.device.diagnostics() ?? "（无诊断信息）"
            let state: String = self.device.currentLockState() ?? "未知"
            DispatchQueue.main.async { [weak self] in
                self?.renderResult(attempt: n, log: log, state: state)
            }
        }
    }

    private func renderResult(attempt: Int, log: String, state: String) {
        actionButton.isEnabled = true
        actionButton.setTitle("重试", for: .normal)
        let locked = state.contains("已锁定")
        titleLabel.text = locked ? "已锁定 ✓ 屏幕应已熄灭" : "锁屏请求未生效"

        var text = "系统状态：\(state)   第 \(attempt) 次尝试\n"
        if !lastCrash.isEmpty {
            text += "\n【上次崩溃记录】\n\(lastCrash)\n"
        }
        text += "\n" + log
        diagnosticsView.text = text
    }

    @objc private func onAction() {
        triggerLock()
    }

    @objc private func onQuit() {
        exit(EXIT_SUCCESS)
    }
}
