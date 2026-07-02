//
//  ARWorldTrackingViewController.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import ARKit
import RealityKit
import simd
import UIKit

final class ARWorldTrackingViewController: UIViewController {
    private let viewModel: ARWorldTrackingViewModel

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

    private let dragHandleContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let grabberView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemGray3
        view.layer.cornerRadius = 2.5
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

    private let debugToggleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 12
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

    private let anchorsButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "cube.transparent")
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let anchorInspectorBackdrop: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.alpha = 0
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let anchorInspectorPanel: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.98)
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let anchorSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["ARAnchor", "AnchorEntity"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let anchorSearchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search by name"
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()

    private let anchorTypeFilterButton: UIButton = {
        var configuration = UIButton.Configuration.gray()
        configuration.title = "Type: All"
        configuration.image = UIImage(systemName: "line.3.horizontal.decrease.circle")
        configuration.imagePadding = 4
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .small
        let button = UIButton(configuration: configuration)
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let anchorListScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let anchorListStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let horizontalSwitch = UISwitch()
    private let verticalSwitch = UISwitch()
    private let lightEstimationSwitch = UISwitch()
    private let sessionIDLabel = UILabel()
    private let cameraTransformLabel = UILabel()
    private let cameraOrientationLabel = UILabel()
    private let trackingStateLabel = UILabel()
    private let lightEstimateLabel = UILabel()

    private var chipGroups: [[UIButton]] = []
    private var isAnchorPanelVisible = false
    private var anchorTypeFilter: String?
    private let maxARAnchorRows = 20
    private var overlayHeightConstraint: NSLayoutConstraint?
    private var panStartHeight: CGFloat = 0
    private var didInitOverlayHeight = false

    private var collapsedOverlayHeight: CGFloat { view.bounds.height * 0.35 }
    private var expandedOverlayHeight: CGFloat { view.bounds.height * 0.85 }

    init(viewModel: ARWorldTrackingViewModel) {
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
        setupAnchorInspector()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didInitOverlayHeight, view.bounds.height > 0 else { return }
        overlayHeightConstraint?.constant = collapsedOverlayHeight
        didInitOverlayHeight = true
    }

    private func setupARView() {
        view.addSubview(arView)
        view.addSubview(backButton)
        view.addSubview(anchorsButton)

        backButton.addAction(UIAction { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)

        anchorsButton.accessibilityLabel = "Anchor list"
        anchorsButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setAnchorPanel(visible: !self.isAnchorPanelVisible)
        }, for: .touchUpInside)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleARTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36),

            anchorsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            anchorsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            anchorsButton.widthAnchor.constraint(equalToConstant: 36),
            anchorsButton.heightAnchor.constraint(equalToConstant: 36)
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

        cameraOrientationLabel.font = .preferredFont(forTextStyle: .caption1)
        cameraOrientationLabel.textColor = .white
        cameraOrientationLabel.numberOfLines = 0
        cameraOrientationLabel.text = "Camera Orientation: -"

        trackingStateLabel.font = .preferredFont(forTextStyle: .caption1)
        trackingStateLabel.textColor = .white
        trackingStateLabel.numberOfLines = 0
        trackingStateLabel.text = "Tracking State: -"

        lightEstimateLabel.font = .preferredFont(forTextStyle: .caption1)
        lightEstimateLabel.textColor = .white
        lightEstimateLabel.numberOfLines = 0
        lightEstimateLabel.text = "Light Estimate: -"

        telemetryStackView.addArrangedSubview(sessionIDLabel)
        telemetryStackView.addArrangedSubview(cameraTransformLabel)
        telemetryStackView.addArrangedSubview(cameraOrientationLabel)
        telemetryStackView.addArrangedSubview(trackingStateLabel)
        telemetryStackView.addArrangedSubview(lightEstimateLabel)

        NSLayoutConstraint.activate([
            telemetryPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            telemetryPanel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 12),
            telemetryPanel.trailingAnchor.constraint(equalTo: anchorsButton.leadingAnchor, constant: -12),

            telemetryStackView.topAnchor.constraint(equalTo: telemetryPanel.topAnchor, constant: 10),
            telemetryStackView.leadingAnchor.constraint(equalTo: telemetryPanel.leadingAnchor, constant: 12),
            telemetryStackView.trailingAnchor.constraint(equalTo: telemetryPanel.trailingAnchor, constant: -12),
            telemetryStackView.bottomAnchor.constraint(equalTo: telemetryPanel.bottomAnchor, constant: -10)
        ])
    }

    private func setupOverlay() {
        view.addSubview(overlayPanel)
        overlayPanel.addSubview(dragHandleContainer)
        dragHandleContainer.addSubview(grabberView)
        overlayPanel.addSubview(lifecycleStackView)
        overlayPanel.addSubview(debugToggleStackView)
        overlayPanel.addSubview(overlayScrollView)
        overlayScrollView.addSubview(contentStackView)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleOverlayPan(_:)))
        dragHandleContainer.addGestureRecognizer(panGesture)

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

        debugToggleStackView.addArrangedSubview(makeDebugToggleButton(
            title: "Feature Points",
            systemName: "circle.dotted",
            isOn: viewModel.showsFeaturePoints
        ) { [weak self] isOn in
            self?.viewModel.showsFeaturePoints = isOn
        })
        debugToggleStackView.addArrangedSubview(makeDebugToggleButton(
            title: "World Alignment",
            systemName: "move.3d",
            isOn: viewModel.showsWorldOrigin
        ) { [weak self] isOn in
            self?.viewModel.showsWorldOrigin = isOn
        })

        addConfigurationSections()

        let heightConstraint = overlayPanel.heightAnchor.constraint(equalToConstant: 300)
        overlayHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            overlayPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,

            dragHandleContainer.topAnchor.constraint(equalTo: overlayPanel.topAnchor),
            dragHandleContainer.leadingAnchor.constraint(equalTo: overlayPanel.leadingAnchor),
            dragHandleContainer.trailingAnchor.constraint(equalTo: overlayPanel.trailingAnchor),
            dragHandleContainer.heightAnchor.constraint(equalToConstant: 28),

            grabberView.centerXAnchor.constraint(equalTo: dragHandleContainer.centerXAnchor),
            grabberView.centerYAnchor.constraint(equalTo: dragHandleContainer.centerYAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 40),
            grabberView.heightAnchor.constraint(equalToConstant: 5),

            lifecycleStackView.topAnchor.constraint(equalTo: dragHandleContainer.bottomAnchor, constant: 8),
            lifecycleStackView.leadingAnchor.constraint(equalTo: overlayPanel.leadingAnchor, constant: 16),
            lifecycleStackView.trailingAnchor.constraint(equalTo: overlayPanel.trailingAnchor, constant: -16),
            lifecycleStackView.heightAnchor.constraint(equalToConstant: 44),

            debugToggleStackView.topAnchor.constraint(equalTo: lifecycleStackView.bottomAnchor, constant: 12),
            debugToggleStackView.leadingAnchor.constraint(equalTo: overlayPanel.leadingAnchor, constant: 16),
            debugToggleStackView.trailingAnchor.constraint(equalTo: overlayPanel.trailingAnchor, constant: -16),
            debugToggleStackView.heightAnchor.constraint(equalToConstant: 44),

            overlayScrollView.topAnchor.constraint(equalTo: debugToggleStackView.bottomAnchor, constant: 16),
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
            self?.cameraOrientationLabel.text = "Camera Orientation: \(state.cameraOrientation)"
            self?.trackingStateLabel.text = "Tracking State: \(state.trackingState)"
            self?.lightEstimateLabel.text = "Light Estimate: \(state.lightEstimate)"
        }

        viewModel.onAnchorsChanged = { [weak self] in
            self?.refreshAnchorListIfVisible()
        }
    }

    private func setupAnchorInspector() {
        view.addSubview(anchorInspectorBackdrop)
        view.addSubview(anchorInspectorPanel)

        let backdropTap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
        anchorInspectorBackdrop.addGestureRecognizer(backdropTap)

        let titleLabel = UILabel()
        titleLabel.text = "Anchors"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        var closeConfig = UIButton.Configuration.plain()
        closeConfig.image = UIImage(systemName: "xmark")
        let closeButton = UIButton(configuration: closeConfig)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in
            self?.setAnchorPanel(visible: false)
        }, for: .touchUpInside)

        anchorSegmentedControl.addAction(UIAction { [weak self] _ in
            self?.anchorTypeFilter = nil
            self?.refreshAnchorList()
        }, for: .valueChanged)

        anchorSearchBar.delegate = self

        anchorInspectorPanel.addSubview(titleLabel)
        anchorInspectorPanel.addSubview(closeButton)
        anchorInspectorPanel.addSubview(anchorSegmentedControl)
        anchorInspectorPanel.addSubview(anchorSearchBar)
        anchorInspectorPanel.addSubview(anchorTypeFilterButton)
        anchorInspectorPanel.addSubview(anchorListScrollView)
        anchorListScrollView.addSubview(anchorListStackView)

        let widthConstraint = anchorInspectorPanel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85)
        widthConstraint.priority = .defaultHigh
        let guide = anchorInspectorPanel.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            anchorInspectorBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            anchorInspectorBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            anchorInspectorBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            anchorInspectorBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            anchorInspectorPanel.topAnchor.constraint(equalTo: view.topAnchor),
            anchorInspectorPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            anchorInspectorPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            widthConstraint,
            anchorInspectorPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

            titleLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            anchorSegmentedControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            anchorSegmentedControl.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            anchorSegmentedControl.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            anchorSearchBar.topAnchor.constraint(equalTo: anchorSegmentedControl.bottomAnchor, constant: 8),
            anchorSearchBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            anchorSearchBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),

            anchorTypeFilterButton.topAnchor.constraint(equalTo: anchorSearchBar.bottomAnchor, constant: 8),
            anchorTypeFilterButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),

            anchorListScrollView.topAnchor.constraint(equalTo: anchorTypeFilterButton.bottomAnchor, constant: 12),
            anchorListScrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            anchorListScrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            anchorListScrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),

            anchorListStackView.topAnchor.constraint(equalTo: anchorListScrollView.contentLayoutGuide.topAnchor),
            anchorListStackView.leadingAnchor.constraint(equalTo: anchorListScrollView.contentLayoutGuide.leadingAnchor),
            anchorListStackView.trailingAnchor.constraint(equalTo: anchorListScrollView.contentLayoutGuide.trailingAnchor),
            anchorListStackView.bottomAnchor.constraint(equalTo: anchorListScrollView.contentLayoutGuide.bottomAnchor),
            anchorListStackView.widthAnchor.constraint(equalTo: anchorListScrollView.frameLayoutGuide.widthAnchor)
        ])

        anchorInspectorPanel.layer.shadowColor = UIColor.black.cgColor
        anchorInspectorPanel.layer.shadowOpacity = 0.2
        anchorInspectorPanel.layer.shadowOffset = CGSize(width: -4, height: 0)
        anchorInspectorPanel.layer.shadowRadius = 8
    }

    private func setAnchorPanel(visible: Bool) {
        isAnchorPanelVisible = visible
        if visible {
            refreshAnchorList()
            view.bringSubviewToFront(anchorInspectorBackdrop)
            view.bringSubviewToFront(anchorInspectorPanel)
            anchorInspectorBackdrop.isHidden = false
            anchorInspectorPanel.isHidden = false
            view.layoutIfNeeded()
            anchorInspectorPanel.transform = CGAffineTransform(translationX: anchorInspectorPanel.bounds.width, y: 0)
            UIView.animate(withDuration: 0.3) {
                self.anchorInspectorPanel.transform = .identity
                self.anchorInspectorBackdrop.alpha = 1
            }
        } else {
            anchorSearchBar.resignFirstResponder()
            UIView.animate(withDuration: 0.3, animations: {
                self.anchorInspectorPanel.transform = CGAffineTransform(translationX: self.anchorInspectorPanel.bounds.width, y: 0)
                self.anchorInspectorBackdrop.alpha = 0
            }, completion: { _ in
                self.anchorInspectorPanel.isHidden = true
                self.anchorInspectorBackdrop.isHidden = true
                self.anchorInspectorPanel.transform = .identity
            })
        }
    }

    @objc private func handleBackdropTap() {
        setAnchorPanel(visible: false)
    }

    private func refreshAnchorListIfVisible() {
        guard isAnchorPanelVisible else { return }
        refreshAnchorList()
    }

    private func refreshAnchorList() {
        anchorListStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = (anchorSearchBar.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let rows: [UIView]
        var truncationNotice: UIView?
        if anchorSegmentedControl.selectedSegmentIndex == 0 {
            let all = viewModel.inspectorARAnchors()
            let types = distinctTypes(all.map(\.type))
            normalizeTypeFilter(types)
            updateTypeFilterMenu(types: types)
            let filtered = all.filter { matchesFilters(type: $0.type, name: $0.name, query: query) }
            let isRefining = !query.isEmpty || anchorTypeFilter != nil
            let visible = isRefining ? filtered : Array(filtered.prefix(maxARAnchorRows))
            rows = visible.map { makeARAnchorRow($0) }
            if !isRefining, filtered.count > visible.count {
                truncationNotice = makeTruncationNoticeRow(shown: visible.count, total: filtered.count)
            }
        } else {
            let all = viewModel.inspectorSceneAnchors()
            let types = distinctTypes(all.map(\.type))
            normalizeTypeFilter(types)
            updateTypeFilterMenu(types: types)
            rows = all
                .filter { matchesFilters(type: $0.type, name: $0.name, query: query) }
                .map { makeSceneAnchorRow($0) }
        }

        if rows.isEmpty {
            anchorListStackView.addArrangedSubview(makeEmptyAnchorRow())
        } else {
            rows.forEach { anchorListStackView.addArrangedSubview($0) }
            if let truncationNotice {
                anchorListStackView.addArrangedSubview(truncationNotice)
            }
        }
    }

    private func matchesFilters(type: String, name: String, query: String) -> Bool {
        (anchorTypeFilter == nil || type == anchorTypeFilter)
            && (query.isEmpty || name.lowercased().contains(query))
    }

    private func distinctTypes(_ types: [String]) -> [String] {
        var seen = Set<String>()
        return types.filter { seen.insert($0).inserted }.sorted()
    }

    private func normalizeTypeFilter(_ types: [String]) {
        if let filter = anchorTypeFilter, !types.contains(filter) {
            anchorTypeFilter = nil
        }
    }

    private func updateTypeFilterMenu(types: [String]) {
        var actions: [UIAction] = [
            UIAction(title: "All", state: anchorTypeFilter == nil ? .on : .off) { [weak self] _ in
                self?.anchorTypeFilter = nil
                self?.refreshAnchorList()
            }
        ]
        for type in types {
            actions.append(UIAction(title: type, state: anchorTypeFilter == type ? .on : .off) { [weak self] _ in
                self?.anchorTypeFilter = type
                self?.refreshAnchorList()
            })
        }
        anchorTypeFilterButton.menu = UIMenu(title: "Filter by type", children: actions)
        anchorTypeFilterButton.configuration?.title = "Type: \(anchorTypeFilter ?? "All")"
    }

    private func makeARAnchorRow(_ anchor: InspectorARAnchor) -> UIView {
        makeAnchorCard(rows: [
            makeAnchorField(title: "name", value: anchor.name),
            makeAnchorField(title: "type", value: anchor.type),
            makeAnchorField(title: "uuid", value: anchor.uuid.uuidString),
            makeAnchorField(title: "transform", value: shortTransform(anchor.transform)),
            makeAnchorField(title: "rendered", value: anchor.isRendered ? "Yes" : "No")
        ])
    }

    private func makeSceneAnchorRow(_ anchor: InspectorSceneAnchor) -> UIView {
        var rows: [UIView] = []
        if !anchor.name.isEmpty {
            rows.append(makeAnchorField(title: "name", value: anchor.name))
        }
        rows.append(makeAnchorField(title: "type", value: anchor.type))
        rows.append(makeAnchorField(title: "uuid", value: anchor.uuid?.uuidString ?? "-"))
        rows.append(makeColorField(color: anchor.color))
        rows.append(makeAnchorField(title: "transform", value: shortTransform(anchor.transform)))
        rows.append(makeAnchorField(title: "anchored", value: anchor.isAnchored ? "Yes" : "No"))
        return makeAnchorCard(rows: rows)
    }

    private func makeAnchorCard(rows: [UIView]) -> UIView {
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return card
    }

    private func makeAnchorField(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.textColor = .secondaryLabel
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .preferredFont(forTextStyle: .caption1)
        valueLabel.numberOfLines = 0
        valueLabel.textAlignment = .right

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .firstBaseline
        return stack
    }

    private func makeColorField(color: UIColor?) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = "color"
        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.textColor = .secondaryLabel
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let swatch = UIView()
        swatch.backgroundColor = color ?? .clear
        swatch.layer.cornerRadius = 4
        swatch.layer.borderWidth = 1
        swatch.layer.borderColor = UIColor.separator.cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 16),
            swatch.heightAnchor.constraint(equalToConstant: 16)
        ])

        let valueLabel = UILabel()
        valueLabel.text = color.map { hexString($0) } ?? "-"
        valueLabel.font = .preferredFont(forTextStyle: .caption1)

        let trailing = UIStackView(arrangedSubviews: [swatch, valueLabel])
        trailing.axis = .horizontal
        trailing.spacing = 6
        trailing.alignment = .center

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, spacer, trailing])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        return stack
    }

    private func makeEmptyAnchorRow() -> UIView {
        let label = UILabel()
        label.text = "(none)"
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }

    private func makeTruncationNoticeRow(shown: Int, total: Int) -> UIView {
        let label = UILabel()
        label.text = "Showing \(shown) of \(total). Search or filter to see all."
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func shortTransform(_ transform: simd_float4x4) -> String {
        let position = transform.columns.3
        return String(format: "x: %.2f, y: %.2f, z: %.2f", position.x, position.y, position.z)
    }

    private func hexString(_ color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    @objc private func handleARTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: arView)
        switch viewModel.handleTap(at: point, in: arView) {
        case .existingAnchor(let info):
            presentAnchorInfoAlert(info)
        case .raycastHit(let transform):
            presentAddAnchorDialog(transform: transform)
        case .noHit:
            break
        }
    }

    @objc private func handleOverlayPan(_ gesture: UIPanGestureRecognizer) {
        guard let overlayHeightConstraint else { return }

        let translationY = gesture.translation(in: view).y
        switch gesture.state {
        case .began:
            panStartHeight = overlayHeightConstraint.constant
        case .changed:
            let proposedHeight = panStartHeight - translationY
            overlayHeightConstraint.constant = min(
                max(proposedHeight, collapsedOverlayHeight),
                expandedOverlayHeight
            )
        case .ended, .cancelled:
            let midpoint = (collapsedOverlayHeight + expandedOverlayHeight) / 2
            let velocityY = gesture.velocity(in: view).y
            let shouldExpand = velocityY < 0
                || (velocityY == 0 && overlayHeightConstraint.constant > midpoint)
            overlayHeightConstraint.constant = shouldExpand ? expandedOverlayHeight : collapsedOverlayHeight
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            }
        default:
            break
        }
    }

    private func presentAnchorInfoAlert(_ info: AnchorTapInfo) {
        let alert = UIAlertController(
            title: info.name,
            message: "UUID: \(info.uuid.uuidString)\nTransform: \(info.transformDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentAddAnchorDialog(transform: simd_float4x4) {
        let dialog = AddAnchorViewController(transform: transform) { [weak self] name, useARAnchor in
            self?.viewModel.addUserAnchor(name: name, transform: transform, useARAnchor: useARAnchor)
        }
        present(dialog, animated: true)
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

    private func makeDebugToggleButton(
        title: String,
        systemName: String,
        isOn: Bool,
        action: @escaping (Bool) -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = UIImage(systemName: systemName)
        configuration.imagePadding = 6
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .preferredFont(forTextStyle: .footnote)
            return updated
        }
        configuration.cornerStyle = .medium
        let button = UIButton(configuration: configuration)
        button.isSelected = isOn
        button.configurationUpdateHandler = { btn in
            btn.configuration?.baseBackgroundColor = btn.isSelected ? .systemBlue : .systemGray5
            btn.configuration?.baseForegroundColor = btn.isSelected ? .white : .label
        }
        button.addAction(UIAction { _ in
            button.isSelected.toggle()
            action(button.isSelected)
        }, for: .touchUpInside)
        return button
    }

    private func makeSectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func makeGroupHeader(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        let base = UIFont.preferredFont(forTextStyle: .title3)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
        label.font = UIFont(descriptor: descriptor, size: 0)
        return label
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
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

    private func addConfigurationSections() {
        contentStackView.addArrangedSubview(makeGroupHeader("ARConfiguration"))

        let alignments: [(title: String, value: ARConfiguration.WorldAlignment)] = [
            ("gravity", .gravity),
            ("gravityAndHeading", .gravityAndHeading),
            ("camera", .camera)
        ]
        contentStackView.addArrangedSubview(makeChipsSection(
            propertyName: "worldAlignment",
            options: alignments,
            selected: viewModel.worldAlignment,
            onSelect: { [weak self] value in self?.viewModel.worldAlignment = value }
        ))

        contentStackView.addArrangedSubview(makeDivider())

        let texturing: [(title: String, value: ARWorldTrackingConfiguration.EnvironmentTexturing)] = [
            ("none", .none),
            ("manual", .manual),
            ("automatic", .automatic)
        ]
        contentStackView.addArrangedSubview(makeChipsSection(
            propertyName: "environmentTexturing",
            options: texturing,
            selected: viewModel.environmentTexturing,
            onSelect: { [weak self] value in self?.viewModel.environmentTexturing = value }
        ))

        contentStackView.addArrangedSubview(makeDivider())

        lightEstimationSwitch.isOn = viewModel.isLightEstimationEnabled
        lightEstimationSwitch.addAction(UIAction { [weak self] _ in
            self?.viewModel.isLightEstimationEnabled = self?.lightEstimationSwitch.isOn ?? false
        }, for: .valueChanged)
        contentStackView.addArrangedSubview(makeToggleSection(
            propertyName: "isLightEstimationEnabled",
            rows: [("enabled", lightEstimationSwitch)]
        ))

        contentStackView.addArrangedSubview(makeDivider())

        horizontalSwitch.isOn = viewModel.isHorizontalPlaneDetectionEnabled
        verticalSwitch.isOn = viewModel.isVerticalPlaneDetectionEnabled
        horizontalSwitch.addAction(UIAction { [weak self] _ in
            self?.viewModel.isHorizontalPlaneDetectionEnabled = self?.horizontalSwitch.isOn ?? false
        }, for: .valueChanged)
        verticalSwitch.addAction(UIAction { [weak self] _ in
            self?.viewModel.isVerticalPlaneDetectionEnabled = self?.verticalSwitch.isOn ?? false
        }, for: .valueChanged)
        contentStackView.addArrangedSubview(makeToggleSection(
            propertyName: "planeDetection",
            rows: [("horizontal", horizontalSwitch), ("vertical", verticalSwitch)]
        ))

        contentStackView.addArrangedSubview(makeDivider())

        contentStackView.addArrangedSubview(makeGroupHeader("ARSession.RunOptions"))
        contentStackView.addArrangedSubview(makeRunOptionsSection())

        contentStackView.addArrangedSubview(makeButtonRow(
            titles: ["Remove All Anchors", "Reset Tracking"],
            actions: [
                { [weak self] in self?.viewModel.removeAllAnchors() },
                { [weak self] in self?.viewModel.resetTracking() }
            ]
        ))
    }

    private func makeRunOptionsSection() -> UIStackView {
        let options: [(title: String, option: ARSession.RunOptions)] = [
            ("resetTracking", .resetTracking),
            ("removeExistingAnchors", .removeExistingAnchors),
            ("resetSceneReconstruction", .resetSceneReconstruction),
            ("stopTrackedRaycasts", .stopTrackedRaycasts)
        ]
        let rows: [(title: String, toggle: UISwitch)] = options.map { option in
            let toggle = UISwitch()
            toggle.isOn = viewModel.runOptions.contains(option.option)
            let value = option.option
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                self?.viewModel.setRunOption(value, enabled: toggle?.isOn ?? false)
            }, for: .valueChanged)
            return (option.title, toggle)
        }
        return makeToggleSection(propertyName: "runOptions", rows: rows)
    }

    private func makeToggleSection(
        propertyName: String,
        rows: [(title: String, toggle: UISwitch)]
    ) -> UIStackView {
        let rowsStack = UIStackView()
        rowsStack.axis = .vertical
        rowsStack.spacing = 8
        for row in rows {
            rowsStack.addArrangedSubview(makeToggleRow(title: row.title, toggle: row.toggle))
        }

        let section = UIStackView(arrangedSubviews: [makeSectionTitle(propertyName), rowsStack])
        section.axis = .vertical
        section.spacing = 8
        return section
    }

    private func makeChipsSection<Value: Equatable>(
        propertyName: String,
        options: [(title: String, value: Value)],
        selected: Value,
        onSelect: @escaping (Value) -> Void
    ) -> UIStackView {
        let groupIndex = chipGroups.count
        var chips: [UIButton] = []
        let chipsStack = UIStackView()
        chipsStack.axis = .horizontal
        chipsStack.spacing = 8
        chipsStack.translatesAutoresizingMaskIntoConstraints = false

        for (index, option) in options.enumerated() {
            let chip = makeChip(title: option.title, isSelected: option.value == selected)
            chip.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.selectChip(groupIndex: groupIndex, selectedIndex: index)
                onSelect(option.value)
            }, for: .touchUpInside)
            chips.append(chip)
            chipsStack.addArrangedSubview(chip)
        }
        chipGroups.append(chips)

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.addSubview(chipsStack)
        NSLayoutConstraint.activate([
            chipsStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            chipsStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            scrollView.heightAnchor.constraint(equalTo: chipsStack.heightAnchor)
        ])

        let section = UIStackView(arrangedSubviews: [makeSectionTitle(propertyName), scrollView])
        section.axis = .vertical
        section.spacing = 8
        return section
    }

    private func makeChip(title: String, isSelected: Bool) -> UIButton {
        UIButton(configuration: chipConfiguration(title: title, isSelected: isSelected))
    }

    private func chipConfiguration(title: String, isSelected: Bool) -> UIButton.Configuration {
        var config = isSelected ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        config.title = title
        config.cornerStyle = .capsule
        config.buttonSize = .small
        return config
    }

    private func selectChip(groupIndex: Int, selectedIndex: Int) {
        for (index, chip) in chipGroups[groupIndex].enumerated() {
            let title = chip.configuration?.title ?? ""
            chip.configuration = chipConfiguration(title: title, isSelected: index == selectedIndex)
        }
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

extension ARWorldTrackingViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        refreshAnchorList()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
