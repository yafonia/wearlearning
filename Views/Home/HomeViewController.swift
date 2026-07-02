//
//  HomeViewController.swift
//  WeAReLearning
//
//  Created by Yafonia Hutabarat on 27/06/26.
//

import UIKit

final class HomeViewController: UIViewController {
    private let viewModel: HomeViewModel
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(HomeCardCell.self, forCellWithReuseIdentifier: HomeCardCell.reuseIdentifier)
        return collectionView
    }()

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AR Learning"
        view.backgroundColor = .systemGroupedBackground
        setupCollectionView()
        configureDataSource()
        applySnapshot()
    }

    private func setupCollectionView() {
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.5),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(140)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item])
        group.interItemSpacing = .fixed(16)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 16
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, identifier in
            guard let item = ARCardItem(rawValue: identifier),
                  let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: HomeCardCell.reuseIdentifier,
                for: indexPath
            ) as? HomeCardCell else {
                return UICollectionViewCell()
            }
            cell.configure(with: item)
            return cell
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(viewModel.items.map(\.rawValue))
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func destinationViewController(for item: ARCardItem) -> UIViewController {
        switch item {
        case .arWorldTracking:
            ARWorldTrackingViewController(viewModel: ARWorldTrackingViewModel())
        }
    }
}

extension HomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let identifier = dataSource?.itemIdentifier(for: indexPath),
              let item = ARCardItem(rawValue: identifier) else { return }
        navigationController?.pushViewController(destinationViewController(for: item), animated: true)
    }
}
