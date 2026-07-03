//
//  AddAnchorViewController.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 02/07/26.
//

import ARKit
import UIKit

// A centered, non-draggable dialog for creating an anchor. It shows the raycast result
// transform (computed before this dialog), lets the user name the anchor, pick the
// AnchorEntity target (World/Plane/Camera), and choose whether it is backed by an
// ARAnchor and/or an AnchorEntity (two checkboxes, both on by default, at least one
// required; "With ARAnchor" is disabled for Plane/Camera). onAdd delivers
// (name, withARAnchor, withAnchorEntity, target).
final class AddAnchorViewController: UIViewController {
    private let onAdd: (String, Bool, Bool, AnchorEntityTarget) -> Void
    private let transform: simd_float4x4?

    private let card: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let nameField: UITextField = {
        let field = UITextField()
        field.placeholder = "Anchor name"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        return field
    }()

    private let targetControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["World", "Plane", "Camera"])
        control.selectedSegmentIndex = AnchorEntityTarget.world.rawValue
        return control
    }()

    private let arAnchorCheckbox = AddAnchorViewController.makeCheckbox(title: "With ARAnchor")
    private let anchorEntityCheckbox = AddAnchorViewController.makeCheckbox(title: "With AnchorEntity")

    // Square imagery signals these are multi-select checkboxes (not radios).
    private static func makeCheckbox(title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: "checkmark.square.fill")
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.isSelected = true
        button.configurationUpdateHandler = { btn in
            let name = btn.isSelected ? "checkmark.square.fill" : "square"
            btn.configuration?.image = UIImage(systemName: name)
        }
        return button
    }

    init(transform: simd_float4x4?, onAdd: @escaping (String, Bool, Bool, AnchorEntityTarget) -> Void) {
        self.transform = transform
        self.onAdd = onAdd
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
        nameField.delegate = self
        arAnchorCheckbox.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.toggle(self.arAnchorCheckbox, other: self.anchorEntityCheckbox)
        }, for: .touchUpInside)
        anchorEntityCheckbox.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.toggle(self.anchorEntityCheckbox, other: self.arAnchorCheckbox)
        }, for: .touchUpInside)
        targetControl.addAction(UIAction { [weak self] _ in
            self?.updateARAnchorAvailability()
        }, for: .valueChanged)
        setupContent()
        updateARAnchorAvailability()
    }

    // Toggle a checkbox, but keep at least one selected.
    private func toggle(_ box: UIButton, other: UIButton) {
        if box.isSelected && !other.isSelected { return }
        box.isSelected.toggle()
    }

    // Plane / Camera targets cannot be backed by a plain ARAnchor(transform:), so
    // "With ARAnchor" is disabled and cleared for those (and "With AnchorEntity" is
    // forced on, since at least one is required); World re-enables both.
    private func updateARAnchorAvailability() {
        let isWorld = targetControl.selectedSegmentIndex == AnchorEntityTarget.world.rawValue
        arAnchorCheckbox.isEnabled = isWorld
        if !isWorld {
            arAnchorCheckbox.isSelected = false
            anchorEntityCheckbox.isSelected = true
        }
        anchorEntityCheckbox.isEnabled = isWorld
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        nameField.becomeFirstResponder()
    }

    private func setupContent() {
        let titleLabel = UILabel()
        titleLabel.text = "Add Anchor"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        let transformLabel = UILabel()
        transformLabel.text = transformText(transform)
        transformLabel.numberOfLines = 0
        transformLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        transformLabel.textColor = .secondaryLabel

        let cancelButton = UIButton(configuration: .gray())
        cancelButton.configuration?.title = "Cancel"
        cancelButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let addButton = UIButton(configuration: .borderedProminent())
        addButton.configuration?.title = "Add"
        addButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [cancelButton, addButton])
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 12

        let targetCaption = UILabel()
        targetCaption.text = "AnchorEntity target"
        targetCaption.font = .preferredFont(forTextStyle: .caption1)
        targetCaption.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            transformLabel,
            nameField,
            targetCaption,
            targetControl,
            arAnchorCheckbox,
            anchorEntityCheckbox,
            buttonRow
        ])
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
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])
    }

    private func transformText(_ t: simd_float4x4?) -> String {
        guard let t else { return "Raycast result: no surface found" }
        let p = t.columns.3
        return String(format: "Raycast result\nx %.3f  y %.3f  z %.3f", p.x, p.y, p.z)
    }

    private func submit() {
        let name = nameField.text ?? ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            nameField.becomeFirstResponder()
            return
        }
        let target = AnchorEntityTarget(rawValue: targetControl.selectedSegmentIndex) ?? .world
        onAdd(name, arAnchorCheckbox.isSelected, anchorEntityCheckbox.isSelected, target)
        dismiss(animated: true)
    }
}

extension AddAnchorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}
