import UIKit
import WebKit
import Photos

final class ImageSchemeHandler: NSObject, WKURLSchemeHandler {
    weak var viewController: MainViewController?
    private let imageManager = PHCachingImageManager()
    private let taskLock = NSLock()
    private var activeTasks = Set<ObjectIdentifier>()
    private var taskRequests: [ObjectIdentifier: PHImageRequestID] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskId = ObjectIdentifier(urlSchemeTask)
        taskLock.lock()
        activeTasks.insert(taskId)
        taskLock.unlock()

        guard let url = urlSchemeTask.request.url else {
            finishTask(urlSchemeTask, status: 400, mime: "text/plain", data: Data("Bad URL".utf8))
            return
        }

        let path = url.path.isEmpty ? "/index.html" : url.path
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = comps?.queryItems ?? []

        func param(_ name: String) -> String? {
            return query.first(where: { $0.name == name })?.value
        }

        // Static assets
        if path == "/" || path == "/index.html" || path.hasPrefix("/static/") {
            let fileName = (path == "/" || path == "/index.html") ? "index.html" : String(path.dropFirst("/static/".count))
            if let data = loadBundledStatic(fileName: fileName) {
                let mime: String
                if fileName.hasSuffix(".html") { mime = "text/html; charset=utf-8" }
                else if fileName.hasSuffix(".css") { mime = "text/css; charset=utf-8" }
                else if fileName.hasSuffix(".js") { mime = "application/javascript; charset=utf-8" }
                else { mime = "application/octet-stream" }
                finishTask(urlSchemeTask, status: 200, mime: mime, data: data)
            } else {
                finishTask(urlSchemeTask, status: 404, mime: "text/plain", data: Data("Not found".utf8))
            }
            return
        }

        let scanner = PhotoScanner.shared

        switch path {
        case "/api/status":
            let json = "{\"scanning\":\(scanner.scanning),\"version\":\(scanner.version),\"mode\":\"\(scanner.viewMode)\"}"
            finishTask(urlSchemeTask, status: 200, mime: "application/json", data: Data(json.utf8))

        case "/api/tree":
            if scanner.scanning || scanner.getTreeJson() == nil {
                finishTask(urlSchemeTask, status: 202, mime: "application/json", data: Data("{\"status\":\"scanning\"}".utf8))
            } else if let data = scanner.getTreeJson() {
                finishTask(urlSchemeTask, status: 200, mime: "application/json", data: data)
            }

        case "/api/set-mode":
            let m = param("mode") ?? "month"
            scanner.scan(mode: m)
            let json = "{\"ok\":true,\"mode\":\"\(scanner.viewMode)\"}"
            finishTask(urlSchemeTask, status: 200, mime: "application/json", data: Data(json.utf8))

        case "/api/rescan":
            scanner.scan(mode: nil)
            finishTask(urlSchemeTask, status: 200, mime: "application/json", data: Data("{\"ok\":true}".utf8))

        case "/api/pick-folder":
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let vc = self.viewController else {
                    self?.finishTask(urlSchemeTask, status: 200, mime: "application/json", data: Data("{\"changed\":false}".utf8))
                    return
                }
                vc.presentAlbumPicker { changed, rootTitle in
                    let escaped = rootTitle.replacingOccurrences(of: "\"", with: "\\\"")
                    let json = "{\"changed\":\(changed),\"root\":\"\(escaped)\"}"
                    self.finishTask(urlSchemeTask, status: 200, mime: "application/json", data: Data(json.utf8))
                }
            }

        case "/api/open-file":
            let id = Int(param("id") ?? "-1") ?? -1
            DispatchQueue.main.async { [weak self] in
                self?.viewController?.sharePhoto(id: id)
            }
            finishTask(urlSchemeTask, status: 200, mime: "application/json", data: Data("{\"ok\":true}".utf8))

        case "/api/thumb":
            let id = Int(param("id") ?? "-1") ?? -1
            servePhoto(task: urlSchemeTask, id: id, size: 160, isThumb: true)

        case "/api/img":
            let id = Int(param("id") ?? "-1") ?? -1
            let rawS = Int(param("s") ?? "512") ?? 512
            let size = max(64, min(4096, rawS))
            servePhoto(task: urlSchemeTask, id: id, size: size, isThumb: size <= 512)

        default:
            finishTask(urlSchemeTask, status: 404, mime: "text/plain", data: Data("Not found".utf8))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskId = ObjectIdentifier(urlSchemeTask)
        taskLock.lock()
        activeTasks.remove(taskId)
        let reqId = taskRequests.removeValue(forKey: taskId)
        taskLock.unlock()
        if let reqId = reqId {
            imageManager.cancelImageRequest(reqId)
        }
    }

    private func loadBundledStatic(fileName: String) -> Data? {
        let ns = fileName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "static"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        if let url = Bundle.main.url(forResource: base, withExtension: ext),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return nil
    }

    private func servePhoto(task: WKURLSchemeTask, id: Int, size: Int, isThumb: Bool) {
        guard let localId = PhotoScanner.shared.getPhotoIdentifier(id) else {
            finishTask(task, status: 404, mime: "text/plain", data: Data())
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let taskId = ObjectIdentifier(task)
            self.taskLock.lock()
            let stillActive = self.activeTasks.contains(taskId)
            self.taskLock.unlock()
            guard stillActive else { return }

            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil).firstObject else {
                self.finishTask(task, status: 404, mime: "text/plain", data: Data())
                return
            }

            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = isThumb ? .fast : .exact
            opts.isSynchronous = false

            let target = CGSize(width: CGFloat(size), height: CGFloat(size))
            let contentMode: PHImageContentMode = size <= 1600 ? .aspectFill : .aspectFit

            let reqId = self.imageManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: contentMode,
                options: opts
            ) { [weak self] image, _ in
                guard let self = self else { return }
                guard let img = image else {
                    self.finishTask(task, status: 404, mime: "text/plain", data: Data())
                    return
                }
                let finalImg: UIImage
                if size <= 1600 {
                    finalImg = self.cropToSquare(img, targetSize: CGFloat(size))
                } else {
                    finalImg = img
                }
                if let jpeg = finalImg.jpegData(compressionQuality: isThumb ? 0.80 : 0.86) {
                    self.finishTask(task, status: 200, mime: "image/jpeg", data: jpeg)
                } else {
                    self.finishTask(task, status: 500, mime: "text/plain", data: Data())
                }
            }

            self.taskLock.lock()
            if self.activeTasks.contains(taskId) {
                self.taskRequests[taskId] = reqId
            }
            self.taskLock.unlock()
        }
    }

    private func cropToSquare(_ image: UIImage, targetSize: CGFloat) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let side = min(w, h)
        let outSide = min(side, targetSize)
        guard outSide > 0 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outSide, height: outSide), format: format)
        return renderer.image { _ in
            let scale = outSide / side
            let drawW = w * scale
            let drawH = h * scale
            let dx = (outSide - drawW) * 0.5
            let dy = (outSide - drawH) * 0.5
            image.draw(in: CGRect(x: dx, y: dy, width: drawW, height: drawH))
        }
    }

    private func finishTask(_ task: WKURLSchemeTask, status: Int, mime: String, data: Data) {
        let taskId = ObjectIdentifier(task)
        taskLock.lock()
        let wasActive = activeTasks.remove(taskId) != nil
        taskRequests.removeValue(forKey: taskId)
        taskLock.unlock()
        guard wasActive else { return }

        let url = task.request.url ?? URL(string: "photogalaxy://app/")!
        let headers: [String: String] = [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": mime.hasPrefix("image/") ? "public, max-age=86400" : "no-store"
        ]
        if let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) {
            task.didReceive(resp)
        }
        task.didReceive(data)
        task.didFinish()
    }
}
