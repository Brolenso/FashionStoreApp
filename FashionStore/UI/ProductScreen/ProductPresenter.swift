//
//  ProductPresenter.swift
//  FashionStore
//
//  Created by Vyacheslav on 07.03.2023.
//

import UIKit

protocol ProductPresenterProtocol: AnyObject {
    func backScreen()
    func showCart()
    func addProductToCart() async throws
    func loadInfo()
    func checkAndLoadFaceImage() async throws
    func checkInCartPresence() async throws
}

final class ProductPresenter: ProductPresenterProtocol {
    weak var view: ProductViewProtocol?
    private let router: Routing
    private let webService: WebServiceProtocol
    private let coreDataService: CoreDataServiceProtocol
    private let product: Product
    private let image: UIImage?

    init(
        router: Routing,
        webService: WebServiceProtocol,
        coreDataService: CoreDataServiceProtocol,
        product: Product,
        image: UIImage?
    ) {
        self.router = router
        self.webService = webService
        self.coreDataService = coreDataService
        self.product = product
        self.image = image
    }

    func loadInfo() {
        view?.fillProduct(
            productBrandLabelTitle: product.brand,
            productNameLabelTitle: product.name,
            productPriceLabelTitle: "$" + product.price.formatted(.number.precision(.fractionLength(0...2))),
            productDescriptionLabelTitle: product.information,
            image: image
        )
    }

    // if no image - load from web
    func checkAndLoadFaceImage() async throws {
        // if image == nil, than load image
        guard image == nil else { return }
        // get image name
        guard let imageName = product.images.first else { return }
        // load image from web
        let image = try await webService.getImage(imageName: imageName)
        // switching run on main queue by calling func fillFaceImage on @MainActor UIViewController
        await view?.fillFaceImage(image: image)
    }

    func backScreen() {
        router.popScreen()
    }

    func showCart() {
        router.showCartScreen()
    }

    func addProductToCart() async throws {
        guard let itemID = product.colors.first?.items.first?.id else { return }
        try await coreDataService.addCartItemToCart(itemID: itemID)
    }

    func checkInCartPresence() async throws {
        guard let itemID = product.colors.first?.items.first?.id else { return }
        let itemInCart = try await coreDataService.checkItemInCart(itemID: itemID)

        if itemInCart {
            await view?.disableAddToCartButton()
        } else {
            await view?.enableAddToCartButton()
        }
    }

}
