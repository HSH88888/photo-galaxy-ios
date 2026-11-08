import UIKit
import WebKit
import Photos

final class MainViewController: UIViewController, WKNavigationDelegate {
    private var webView: WKWebView!
    private let schemeHandler = ImageSchemeHandler()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 13/255, green: 13/255, blue: 23/255, alpha: 1.0)

        schemeHandler.viewController = self

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "photogalaxy")
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])

        requestPhotoPermissionAndLoad()
    }

    private func requestPhotoPermissionAndLoad() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.startScannerAndLoadWeb()
                }
            }
        } else {
            startScannerAndLoadWeb()
        }
    }

    private func startScannerAndLoadWeb() {
        PhotoScanner.shared.scan(mode: "month")
        if let url = URL(string: "photogalaxy://app/index.html") {
            webView.load(URLRequest(url: url))
        }
    }

    func presentAlbumPicker(completion: @escaping (Bool, String) -> Void) {
        let albums = PhotoScanner.shared.listAlbums()
        let alert = UIAlertController(
            title: "사진 범위(앨범) 선택",
            message: "은하계로 표시할 아이폰 앨범을 선택하세요.",
            preferredStyle: .actionSheet
        )

        for album in albums.prefix(25) {
            let label = "\(album.title) (\(album.count)장)"
            alert.addAction(UIAlertAction(title: label, style: .default) { _ in
                PhotoScanner.shared.setAlbumFilter(id: album.localIdentifier, title: album.title)
                completion(true, album.title)
            })
        }

        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in
            completion(false, PhotoScanner.shared.selectedAlbumTitle)
        })

        if let pop = alert.popoverPresentationController {
            pop.sourceView = self.view
            pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.maxY - 60, width: 1, height: 1)
        }

        present(alert, animated: true)
    }

    func sharePhoto(id: Int) {
        guard let localId = PhotoScanner.shared.getPhotoIdentifier(id),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil).firstObject else {
            return
        }

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.isSynchronous = false

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                let vc = UIActivityViewController(activityItems: [img], applicationActivities: nil)
                if let pop = vc.popoverPresentationController {
                    pop.sourceView = self.view
                    pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.maxY - 80, width: 1, height: 1)
                }
                self.present(vc, animated: true)
            }
        }
    }
}
