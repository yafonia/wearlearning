//
//  AddAnchorViewController.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 02/07/26.
//

import simd
import UIKit

// A centered, non-draggable dialog for creating an anchor at a raycast hit. Lets the
// user name it and toggle whether it is backed by an ARAnchor (a radio, on by
// default). onAdd delivers (name, useARAnchor).
final class AddAnchorViewController: UIViewController {
    private let transform: simd_float4x4
    private let onAdd: (String, Bool) -> Void

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

    private let arAnchorRadio: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "With ARAnchor"
        config.image = UIImage(systemName: "largecircle.fill.circle")
        config.imagePadding = 8
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.isSelected = true
        button.configurationUpdateHandler = { btn in
            btn.configuration?.image = UIImage(systemName: btn.isSelected ? "largecircle.fill.circle" : "circle")
        }
        return button
    }()

    init(transform: simd_float4x4, onAdd: @escaping (String, Bool) -> Void) {
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
        arAnchorRadio.addAction(UIAction { [weak self] _ in
            self?.arAnchorRadio.isSelected.toggle()
        }, for: .touchUpInside)
        setupContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        nameField.becomeFirstResponder()
    }

    private func setupContent() {
        let titleLabel = UILabel()
        titleLabel.text = "Add Anchor"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        let position = transform.columns.3
        let transformLabel = UILabel()
        transformLabel.text = String(
            format: "Transform  x: %.3f, y: %.3f, z: %.3f",
            position.x,
            position.y,
            position.z
        )
        transformLabel.font = .preferredFont(forTextStyle: .caption1)
        transformLabel.textColor = .secondaryLabel
        transformLabel.numberOfLines = 0

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

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            transformLabel,
            nameField,
            arAnchorRadio,
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

    private func submit() {
        let name = nameField.text ?? ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            nameField.becomeFirstResponder()
            return
        }
        onAdd(name, arAnchorRadio.isSelected)
        dismiss(animated: true)
    }
}

extension AddAnchorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}
