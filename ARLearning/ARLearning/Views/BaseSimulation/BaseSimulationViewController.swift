//
//  BaseSimulationViewController.swift
//  ARLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import RealityKit
import UIKit

final class BaseSimulationViewController: UIViewController {
    private let viewModel: BaseSimulationViewModel

    private let arView: ARView = {
        let view = ARView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let backButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "chevron.backward")
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let telemetryPanel: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let telemetryStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let overlayPanel: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let lifecycleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 16
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let overlayScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private let contentStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let horizontalSwitch = UISwitch()
    private let verticalSwitch = UISwitch()
    private let sessionIDLabel = UILabel()
    private let cameraTransformLabel = UILabel()
    private let trackingStateLabel = UILabel()
    private let anchorsListLabel = UILabel()

    init(viewModel: BaseSimulationViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupARView()
        setupTelemetryPanel()
        setupOverlay()
        bindViewModel()
        viewModel.attach(to: arView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.pause()
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func setupARView() {
        view.addSubview(arView)
        view.addSubview(backButton)

        backButton.addAction(UIAction { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func setupTelemetryPanel() {
        view.addSubview(telemetryPanel)
        telemetryPanel.addSubview(telemetryStackView)

        sessionIDLabel.font = .preferredFont(forTextStyle: .caption1)
        sessionIDLabel.textColor = .white
        sessionIDLabel.numberOfLines = 0
        sessionIDLabel.text = "Session ID: -"

        cameraTransformLabel.font = .preferredFont(forTextStyle: .caption1)
        cameraTransformLabel.textColor = .white
        cameraTransformLabel.numberOfLines = 0
        cameraTransformLabel.text = "Camera Transform: -"

        trackingStateLabel.font = .preferredFont(forTextStyle: .caption1)
        trackingStateLabel.textColor = .white
        trackingStateLabel.numberOfLines = 0
        trackingStateLabel.text = "Tracking State: -"

        anchorsListLabel.font = .preferredFont(forTextStyle: .caption2)
        anchorsListLabel.textColor = .white
        anchorsListLabel.numberOfLines = 0
        anchorsListLabel.text = "Anchors: (none)"

        telemetryStackView.addArrangedSubview(sessionIDLabel)
        telemetryStackView.addArrangedSubview(cameraTransformLabel)
        telemetryStackView.addArrangedSubview(trackingStateLabel)
        telemetryStackView.addArrangedSubview(anchorsListLabel)

        NSLayoutConstraint.activate([
            telemetryPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            telemetryPanel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 12),
            telemetryPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            telemetryStackView.topAnchor.constraint(equalTo: telemetryPanel.topAnchor, constant: 10),
            telemetryStackView.leadingAnchor.constraint(equalTo: telemetryPanel.leadingAnchor, constant: 12),
            telemetryStackView.trailingAnchor.constraint(equalTo: telemetryPanel.trailingAnchor, constant: -12),
            telemetryStackView.bottomAnchor.constraint(equalTo: telemetryPanel.bottomAnchor, constant: -10)
        ])
    }

    private func setupOverlay() {
        view.addSubview(overlayPanel)
        overlayPanel.addSubview(lifecycleStackView)
        overlayPanel.addSubview(overlayScrollView)
        overlayScrollView.addSubview(contentStackView)

        lifecycleStackView.addArrangedSubview(makeLifecycleButton(
            systemName: "play.fill",
            accessibilityLabel: "Run"
        ) { [weak self] in
            self?.viewModel.run()
        })
        lifecycleStackView.addArrangedSubview(makeLifecycleButton(
            systemName: "pause.fill",
            accessibilityLabel: "Pause"
        ) { [weak self] in
            self?.viewModel.pause()
        })
        lifecycleStackView.addArrangedSubview(makeLifecycleButton(
            systemName: "arrow.counterclockwise",
            accessibilityLabel: "Reset"
        ) { [weak self] in
            self?.viewModel.reset()
        })

        horizontalSwitch.isOn = viewModel.isHorizontalPlaneDetectionEnabled
        verticalSwitch.isOn = viewModel.isVerticalPlaneDetectionEnabled

        horizontalSwitch.addAction(UIAction { [weak self] _ in
            self?.viewModel.isHorizontalPlaneDetectionEnabled = self?.horizontalSwitch.isOn ?? false
        }, for: .valueChanged)

        verticalSwitch.addAction(UIAction { [weak self] _ in
            self?.viewModel.isVerticalPlaneDetectionEnabled = self?.verticalSwitch.isOn ?? false
        }, for: .valueChanged)

        contentStackView.addArrangedSubview(makeSectionTitle("World Tracking Plane Detection"))
        contentStackView.addArrangedSubview(makeToggleRow(title: "Horizontal", toggle: horizontalSwitch))
        contentStackView.addArrangedSubview(makeToggleRow(title: "Vertical", toggle: verticalSwitch))

        contentStackView.addArrangedSubview(makeButtonRow(
            titles: ["Remove All Anchors", "Reset Tracking"],
            actions: [
                { [weak self] in self?.viewModel.removeAllAnchors() },
                { [weak self] in self?.viewModel.resetTracking() }
            ]
        ))

        NSLayoutConstraint.activate([
            overlayPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayPanel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.35),

            lifecycleStackView.topAnchor.constraint(equalTo: overlayPanel.topAnchor, constant: 16),
            lifecycleStackView.leadingAnchor.constraint(equalTo: overlayPanel.leadingAnchor, constant: 16),
            lifecycleStackView.trailingAnchor.constraint(equalTo: overlayPanel.trailingAnchor, constant: -16),
            lifecycleStackView.heightAnchor.constraint(equalToConstant: 44),

            overlayScrollView.topAnchor.constraint(equalTo: lifecycleStackView.bottomAnchor, constant: 16),
            overlayScrollView.leadingAnchor.constraint(equalTo: overlayPanel.leadingAnchor, constant: 16),
            overlayScrollView.trailingAnchor.constraint(equalTo: overlayPanel.trailingAnchor, constant: -16),
            overlayScrollView.bottomAnchor.constraint(equalTo: overlayPanel.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            contentStackView.topAnchor.constraint(equalTo: overlayScrollView.contentLayoutGuide.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: overlayScrollView.contentLayoutGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: overlayScrollView.contentLayoutGuide.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: overlayScrollView.contentLayoutGuide.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: overlayScrollView.frameLayoutGuide.widthAnchor)
        ])

        overlayPanel.layer.shadowColor = UIColor.black.cgColor
        overlayPanel.layer.shadowOpacity = 0.2
        overlayPanel.layer.shadowOffset = CGSize(width: 0, height: -4)
        overlayPanel.layer.shadowRadius = 8

        view.bringSubviewToFront(telemetryPanel)
        view.bringSubviewToFront(overlayPanel)
        view.bringSubviewToFront(backButton)
    }

    private func bindViewModel() {
        viewModel.onDisplayStateUpdated = { [weak self] state in
            self?.sessionIDLabel.text = "Session ID: \(state.sessionID)"
            self?.cameraTransformLabel.text = "Camera Transform: \(state.cameraTransform)"
            self?.trackingStateLabel.text = "Tracking State: \(state.trackingState)"
        }

        viewModel.onAnchorsListUpdated = { [weak self] text in
            self?.anchorsListLabel.text = text
        }
    }

    private func makeLifecycleButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(systemName: systemName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeSectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func makeToggleRow(title: String, toggle: UISwitch) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)

        let stackView = UIStackView(arrangedSubviews: [label, toggle])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        return stackView
    }

    private func makeButtonRow(titles: [String], actions: [() -> Void]) -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually

        for (index, title) in titles.enumerated() {
            var configuration = UIButton.Configuration.gray()
            configuration.title = title
            let button = UIButton(configuration: configuration)
            let action = actions[index]
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }

        return stackView
    }
}
