//
//  RaycastTargetViewController.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 03/07/26.
//

import ARKit
import UIKit

// A centered, non-draggable dialog shown between the Raycast method and Add Anchor
// dialogs for the methods that take an ARRaycastQuery.Target. onContinue delivers the
// chosen target.
final class RaycastTargetViewController: UIViewController {
    private let onContinue: (ARRaycastQuery.Target) -> Void

    private let options: [(title: String, target: ARRaycastQuery.Target)] = [
        ("existingPlaneGeometry", .existingPlaneGeometry),
        ("existingPlaneInfinite", .existingPlaneInfinite),
        ("estimatedPlane", .estimatedPlane)
    ]
    private var selectedIndex = 2 // estimatedPlane
    private var optionButtons: [UIButton] = []

    private let card: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(onContinue: @escaping (ARRaycastQuery.Target) -> Void) {
        self.onContinue = onContinue
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        setupContent()
        updateOptionSelection()
    }

    private func setupContent() {
        let titleLabel = UILabel()
        titleLabel.text = "ARRaycastQuery.Target"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        let optionsStack = UIStackView()
        optionsStack.axis = .vertical
        optionsStack.spacing = 4
        for (index, option) in options.enumerated() {
            let button = makeOptionButton(title: option.title, index: index)
            optionButtons.append(button)
            optionsStack.addArrangedSubview(button)
        }

        let cancelButton = UIButton(configuration: .gray())
        cancelButton.configuration?.title = "Cancel"
        cancelButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let continueButton = UIButton(configuration: .borderedProminent())
        continueButton.configuration?.title = "Continue"
        continueButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [cancelButton, continueButton])
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 12

        let stack = UIStackView(arrangedSubviews: [titleLabel, optionsStack, buttonRow])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(card)
        card.addSubview(stack)

        let centerY = card.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        centerY.priority = .defaultHigh
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 340)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerY,
            preferredWidth,
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])
    }

    private func makeOptionButton(title: String, index: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: "circle")
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in
            self?.selectedIndex = index
            self?.updateOptionSelection()
        }, for: .touchUpInside)
        return button
    }

    private func updateOptionSelection() {
        for (index, button) in optionButtons.enumerated() {
            let isSelected = index == selectedIndex
            button.configuration?.image = UIImage(systemName: isSelected ? "largecircle.fill.circle" : "circle")
        }
    }

    private func submit() {
        let target = options[selectedIndex].target
        // Present the next step only after this dialog finishes dismissing, so the
        // presenter is free to present the Add Anchor dialog.
        dismiss(animated: true) { [onContinue] in
            onContinue(target)
        }
    }
}
