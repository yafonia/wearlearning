//
//  PlaceholderDetailViewController.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import UIKit

final class PlaceholderDetailViewController: UIViewController {
    private let featureTitle: String

    init(title: String) {
        self.featureTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        self.title = featureTitle
    }
}
