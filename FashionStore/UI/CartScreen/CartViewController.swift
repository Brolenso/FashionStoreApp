//
//  CartViewController.swift
//  FashionStore
//
//  Created by Vyacheslav on 28.02.2023.
//

import UIKit
import SnapKit

protocol CartViewProtocol: AnyObject {
    func showEmptyCartWithAnimation()
    func showFullCart()
    func setTotalPrice(price: Decimal?)
    func reloadCollectionViewData()
    func updateCollectionViewItems(updatedItemIDs: [CatalogItem.ID])
}

final class CartViewController: UIViewController {

    private static let headerTitle = "Cart"
    private static let cartIsEmptyTitle = "Your card is empty.\nChoose the best goods from our catalog"
    private static let continueShoppingButtonTitle = "Continue shopping"
    private static let checkoutButtonTitle = "Checkout"
    private static let totalLabelTitle = "Total"
    private static let currencySign = "$"

    private let presenter: CartPresenterProtocol

    private lazy var closeScreenAction: () -> Void = { [weak presenter] in
        presenter?.closeScreen()
    }

    private lazy var closableHeaderView = HeaderNamedView(closeScreenAction: closeScreenAction, headerTitle: Self.headerTitle)

    private var cartItemsCollectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?

    private let cartIsEmptyLabel: UILabel = {
        let label = UILabel.makeLabel(numberOfLines: 0)
        label.isHidden = true
        return label
    }()

    private lazy var checkoutAction: () -> Void = { [weak presenter] in
        presenter?.showCheckout()
    }

    private lazy var footerTotalPriceView = FooterTotalPriceView(
        totalLabelTitle: Self.totalLabelTitle,
        currencySign: Self.currencySign,
        buttonAction: checkoutAction,
        buttonTitle: Self.checkoutButtonTitle
    )

    private lazy var continueShoppingButton = UIButton.makeDarkButton(imageName: ImageName.cartDark, action: closeScreenAction)

    init(presenter: CartPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        Task<Void, Never> { [weak presenter] in
            do {
                // load catalog from Web
                try await presenter?.loadCatalog()
                // check cartItems for availability in the catalog, pop-up message when deleting from cart
                try await presenter?.checkCartInStock()
            } catch {
                Errors.handler.checkError(error)
            }
        }

        // create and configure collection view
        configureCollectionView()

        // setup texts with styles
        setupUiTexts()
        registerFontScaling()

        // arrange layouts
        arrangeLayout()

        // configure collection view data source
        configureDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // turn off navigation swipe, the extension is below
        // turn navigation swipe back on is in viewWillDisappear
        navigationController?.interactivePopGestureRecognizer?.delegate = self

        Task<Void, Never> { [weak presenter] in
            do {
                // reload cart items
                try await presenter?.reloadCart()
                presenter?.reloadCollectionView()
            } catch {
                Errors.handler.checkError(error)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // turn navigation swipe back on
        if let gestureRecognizer = navigationController?.interactivePopGestureRecognizer,
           let delegate = navigationController as? any UIGestureRecognizerDelegate {
            gestureRecognizer.delegate = delegate
        }
    }

    private func setupUiTexts() {
        cartIsEmptyLabel.attributedText = Self.cartIsEmptyTitle.setStyle(style: .bodyLargeAlignCentered)
        continueShoppingButton.configuration?.attributedTitle = AttributedString(
            Self.continueShoppingButtonTitle.uppercased().setStyle(style: .buttonDark)
        )
    }

    // accessibility settings was changed - scale fonts
    private func registerFontScaling() {
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            if self.traitCollection.preferredContentSizeCategory != previousTraitCollection.preferredContentSizeCategory {
                self.setupUiTexts()
                self.cartItemsCollectionView?.collectionViewLayout.invalidateLayout()
            }
        }
    }

    private func arrangeLayout() {
        arrangeClosableHeaderView()
        arrangeCartItemsCollectionView()
        arrangeCartIsEmptyLabel()
        arrangeContinueShoppingButton()
        arrangeFooterTotalPriceView()
        arrangeCartItemsCollectionViewBottom()
    }

    private func arrangeClosableHeaderView() {
        view.addSubview(closableHeaderView)
        closableHeaderView.snp.makeConstraints { make in
            make.left.right.top.equalTo(view.safeAreaLayoutGuide)
        }
    }

    private func arrangeCartItemsCollectionView() {
        guard let cartItemsCollectionView else { return }
        view.addSubview(cartItemsCollectionView)
        cartItemsCollectionView.snp.makeConstraints { make in
            make.top.equalTo(closableHeaderView.snp.bottom).offset(5)
            make.left.right.equalToSuperview()
            // bottom is in footer constraints
        }
    }

    private func arrangeCartIsEmptyLabel() {
        view.addSubview(cartIsEmptyLabel)
        cartIsEmptyLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(240)
            make.left.right.equalToSuperview().inset(16)
        }
    }

    private func arrangeContinueShoppingButton() {
        view.addSubview(continueShoppingButton)
        continueShoppingButton.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview().inset(34)
            make.height.equalTo(50)
        }
    }

    private func arrangeFooterTotalPriceView() {
        view.addSubview(footerTotalPriceView)
        footerTotalPriceView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }
    }

    private func arrangeCartItemsCollectionViewBottom() {
        guard let cartItemsCollectionView else { return }
        cartItemsCollectionView.snp.makeConstraints { make in
            make.bottom.equalTo(footerTotalPriceView.snp.top).offset(-8)
        }
    }

}

extension CartViewController: CartViewProtocol {

    func showEmptyCartWithAnimation() {

        // show gradually
        cartIsEmptyLabel.alpha = 0
        continueShoppingButton.alpha = 0

        // show
        cartIsEmptyLabel.isHidden = false
        continueShoppingButton.isHidden = false

        // show to actual user interaction
        view.bringSubviewToFront(cartIsEmptyLabel)
        view.bringSubviewToFront(continueShoppingButton)

        // hide
        footerTotalPriceView.isHidden = true

        // animations
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.allowUserInteraction],
            animations: { [weak self] in
                guard let self, let cartItemsCollectionView else { return }
                // show
                cartIsEmptyLabel.alpha = 1
                continueShoppingButton.alpha = 1
                // hide
                footerTotalPriceView.alpha = 0
                // remake cartItemsCollectionView constraints
                cartItemsCollectionView.snp.remakeConstraints { [weak self] make in
                    guard let self else { return }
                    make.top.equalTo(closableHeaderView.snp.bottom).offset(5)
                    make.left.right.equalToSuperview()
                    make.bottom.equalTo(continueShoppingButton.snp.top).offset(-8)
                }
            },
            completion: { [weak self] _ in
                guard let self else { return }
                // hide
                footerTotalPriceView.isHidden = true
            }
        )
    }

    func showFullCart() {
        // show
        footerTotalPriceView.isHidden = false
        // hide
        cartIsEmptyLabel.isHidden = true
        continueShoppingButton.isHidden = true
        // remake cartItemsCollectionView constraints
        guard let cartItemsCollectionView else { return }
        cartItemsCollectionView.snp.remakeConstraints { [weak self] make in
            guard let self else { return }
            make.top.equalTo(closableHeaderView.snp.bottom).offset(5)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(footerTotalPriceView.snp.top).offset(-8)
        }
    }

    func setTotalPrice(price: Decimal?) {
        footerTotalPriceView.setTotalPrice(price: price)
    }

}

// collection view implementing
extension CartViewController {

    // create and configure collection view
    private func configureCollectionView() {
        // flow layout creating
        let collectionViewFlowLayout = UICollectionViewFlowLayout()
        // layout setup, automaticSize requires func preferredLayoutAttributesFitting() in cell class
        collectionViewFlowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        collectionViewFlowLayout.sectionInset = CartItemsFlowLayoutConstants.sectionInset
        collectionViewFlowLayout.minimumLineSpacing = CartItemsFlowLayoutConstants.lineSpacing
        collectionViewFlowLayout.minimumInteritemSpacing = CartItemsFlowLayoutConstants.minimumInteritemSpacing

        cartItemsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewFlowLayout)
        // some setup of collection view
        cartItemsCollectionView?.alwaysBounceVertical = true // springing (bounce)
        cartItemsCollectionView?.showsVerticalScrollIndicator = false // no scroll indicator
    }

    private enum Section: Hashable {
        case cartItemSection
    }

    private enum Item: Hashable {
        case cartItem(CatalogItem.ID)
    }

    private func createCartItemCellRegistration() -> UICollectionView.CellRegistration<CartItemCellView, CatalogItem.ID> {
        return UICollectionView.CellRegistration<CartItemCellView, CatalogItem.ID> { [weak self] cell, _, itemID in

            guard let self else { return }

            let loadImageAction: (String) async throws -> UIImage? = { [weak presenter] imageName in
                // load image by presenter
                return try await presenter?.loadImage(imageName: imageName)
            }

            let minusButtonAction: (UUID, Int) async throws -> Void = { [weak presenter] itemID, newCount in
                try await presenter?.reduceCartItemCount(itemID: itemID, newCount: newCount)
            }

            let plusButtonAction: (UUID, Int) async throws -> Void = { [weak presenter] itemID, newCount in
                try await presenter?.increaseCartItemCount(itemID: itemID, newCount: newCount)
            }

            // find info in catalog
            guard let product = presenter.findProduct(itemID: itemID) else { return }
            guard let color = presenter.findColor(itemID: itemID) else { return }
            guard let catalogItem = presenter.findCatalogItem(itemID: itemID) else { return }
            guard let cartItem = presenter.findCartItem(itemID: itemID) else { return }

            let productName = product.name
            let colorName = color.name
            let size = catalogItem.size

            cell.setup(
                imageName: color.images.first,
                loadImageAction: loadImageAction,
                itemBrand: product.brand,
                itemNameColorSize: "\(productName), \(colorName), \(size)",
                itemID: itemID,
                minusButtonAction: minusButtonAction,
                count: cartItem.count,
                plusButtonAction: plusButtonAction,
                itemPrice: product.price
            )
        }
    }

    private func configureDataSource() {
        let cartItemCellRegistration = createCartItemCellRegistration()

        guard let cartItemsCollectionView else { return }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: cartItemsCollectionView
        ) {collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .cartItem(let itemID):
                return collectionView.dequeueConfiguredReusableCell(using: cartItemCellRegistration, for: indexPath, item: itemID)
            }
        }
    }

    func reloadCollectionViewData() {
        guard let dataSource, let cartItems = presenter.getCartItems() else { return }

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        // adding sections to snapshot
        snapshot.appendSections([.cartItemSection])
        // adding products to snapshot by Item enum entities .product(Product)
        snapshot.appendItems(cartItems.map { Item.cartItem($0.itemID) })
        // apply dataSource with correct animations
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    // if count changes
    func updateCollectionViewItems(updatedItemIDs: [CatalogItem.ID]) {
        guard let dataSource else { return }

        var snapshot = dataSource.snapshot()
        let updatedCartItems = updatedItemIDs.compactMap { presenter.findCartItem(itemID: $0) }
        let updatedItems = updatedCartItems.map { Item.cartItem($0.itemID) }
        snapshot.reconfigureItems(updatedItems)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

}

// turn off navigation swipes
extension CartViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}
