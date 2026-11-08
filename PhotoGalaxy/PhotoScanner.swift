import Foundation
import Photos

struct PhotoItem {
    let localIdentifier: String
    let name: String
    let relDir: String
}

struct AlbumOption {
    let localIdentifier: String?
    let title: String
    let count: Int
}

final class PhotoScanner {
    static let shared = PhotoScanner()

    private let lock = NSLock()
    private var _scanning: Bool = true
    private var _version: Int = 0
    private var _viewMode: String = "month"
    private var _selectedAlbumId: String? = nil
    private var _selectedAlbumTitle: String = "아이폰 전체 사진"
    private var photos: [PhotoItem] = []
    private var treeJsonData: Data? = nil

    var scanning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _scanning
    }

    var version: Int {
        lock.lock(); defer { lock.unlock() }
        return _version
    }

    var viewMode: String {
        lock.lock(); defer { lock.unlock() }
        return _viewMode
    }

    var selectedAlbumTitle: String {
        lock.lock(); defer { lock.unlock() }
        return _selectedAlbumTitle
    }

    func getPhotoIdentifier(_ id: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard id >= 0 && id < photos.count else { return nil }
        return photos[id].localIdentifier
    }

    func getTreeJson() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return treeJsonData
    }

    func setAlbumFilter(id: String?, title: String) {
        lock.lock()
        _selectedAlbumId = id
        _selectedAlbumTitle = title
        lock.unlock()
        scan(mode: nil)
    }

    func listAlbums() -> [AlbumOption] {
        var result: [AlbumOption] = []
        let allAssets = PHAsset.fetchAssets(with: .image, options: nil)
        result.append(AlbumOption(localIdentifier: nil, title: "아이폰 전체 사진", count: allAssets.count))

        let smartSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites,
            .smartAlbumScreenshots,
            .smartAlbumSelfPortraits,
            .smartAlbumPanoramas
        ]
        for sub in smartSubtypes {
            let cols = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil)
            cols.enumerateObjects { col, _, _ in
                let assets = PHAsset.fetchAssets(in: col, options: self.imageOnlyOptions())
                if assets.count > 0 {
                    result.append(AlbumOption(
                        localIdentifier: col.localIdentifier,
                        title: col.localizedTitle ?? "스마트 앨범",
                        count: assets.count
                    ))
                }
            }
        }

        let userCols = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userCols.enumerateObjects { col, _, _ in
            let assets = PHAsset.fetchAssets(in: col, options: self.imageOnlyOptions())
            if assets.count > 0 {
                result.append(AlbumOption(
                    localIdentifier: col.localIdentifier,
                    title: col.localizedTitle ?? "앨범",
                    count: assets.count
                ))
            }
        }
        return result
    }

    private func imageOnlyOptions() -> PHFetchOptions {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return opts
    }

    func scan(mode: String? = nil) {
        lock.lock()
        if let m = mode, ["folder", "month", "day"].contains(m) {
            _viewMode = m
        }
        let activeMode = _viewMode
        let activeAlbumId = _selectedAlbumId
        let activeAlbumTitle = _selectedAlbumTitle
        _scanning = true
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            self.performScan(mode: activeMode, albumId: activeAlbumId, albumTitle: activeAlbumTitle)
        }
    }

    private final class Node {
        let name: String
        let parentIdx: Int
        var idx: Int = 0
        var children: [String: Node] = [:]
        var photos: [PhotoItem] = []

        init(name: String, parentIdx: Int) {
            self.name = name
            self.parentIdx = parentIdx
        }
    }

    private func performScan(mode: String, albumId: String?, albumTitle: String) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let authorized = (status == .authorized || status == .limited)

        var rawItems: [PhotoItem] = []

        if authorized {
            var albumMap: [String: String] = [:]
            if mode == "folder" && albumId == nil {
                let smartSubtypes: [PHAssetCollectionSubtype] = [
                    .smartAlbumFavorites,
                    .smartAlbumScreenshots,
                    .smartAlbumSelfPortraits,
                    .smartAlbumPanoramas
                ]
                for sub in smartSubtypes {
                    let cols = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil)
                    cols.enumerateObjects { col, _, _ in
                        let title = col.localizedTitle ?? "스마트 앨범"
                        let assets = PHAsset.fetchAssets(in: col, options: self.imageOnlyOptions())
                        assets.enumerateObjects { asset, _, _ in
                            albumMap[asset.localIdentifier] = "스마트 앨범/\(title)"
                        }
                    }
                }
                let userCols = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
                userCols.enumerateObjects { col, _, _ in
                    let title = col.localizedTitle ?? "내 앨범"
                    let assets = PHAsset.fetchAssets(in: col, options: self.imageOnlyOptions())
                    assets.enumerateObjects { asset, _, _ in
                        albumMap[asset.localIdentifier] = "내 앨범/\(title)"
                    }
                }
            }

            let fetchOpts = imageOnlyOptions()
            fetchOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

            let fetchResult: PHFetchResult<PHAsset>
            if let aid = albumId,
               let col = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [aid], options: nil).firstObject {
                fetchResult = PHAsset.fetchAssets(in: col, options: fetchOpts)
            } else {
                fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOpts)
            }

            let cal = Calendar.current
            rawItems.reserveCapacity(fetchResult.count)

            fetchResult.enumerateObjects { asset, idx, _ in
                let dt = asset.creationDate ?? asset.modificationDate ?? Date()
                let comps = cal.dateComponents([.year, .month, .day], from: dt)
                let y = comps.year ?? 2024
                let m = comps.month ?? 1
                let d = comps.day ?? 1

                let relDir: String
                switch mode {
                case "month":
                    relDir = String(format: "%04d년/%02d월", y, m)
                case "day":
                    relDir = String(format: "%04d년/%02d월/%02d일", y, m, d)
                default:
                    if let mapped = albumMap[asset.localIdentifier] {
                        relDir = mapped
                    } else if albumId != nil {
                        relDir = String(format: "%@/%04d년", albumTitle, y)
                    } else {
                        relDir = String(format: "카메라 롤/%04d년/%02d월", y, m)
                    }
                }

                let shortId = String(asset.localIdentifier.prefix(8)).replacingOccurrences(of: "/", with: "_")
                let name = String(format: "IMG_%04d%02d%02d_%@_%d.JPG", y, m, d, shortId, idx)
                rawItems.append(PhotoItem(localIdentifier: asset.localIdentifier, name: name, relDir: relDir))
            }
        }

        let rootNameLabel = albumId == nil ? "내 아이폰 사진" : albumTitle
        let root = Node(name: rootNameLabel, parentIdx: -1)

        for item in rawItems {
            var cur = root
            if !item.relDir.isEmpty {
                let parts = item.relDir.split(separator: "/").map(String.init)
                for part in parts where !part.isEmpty {
                    if let next = cur.children[part] {
                        cur = next
                    } else {
                        let created = Node(name: part, parentIdx: -1)
                        cur.children[part] = created
                        cur = created
                    }
                }
            }
            cur.photos.append(item)
        }

        var orderedNodes: [Node] = []
        var parentIndices: [Int] = []
        var orderedPhotos: [PhotoItem] = []
        var photoStarts: [Int] = []
        var photoCounts: [Int] = []

        func dfs(_ node: Node, parentIdx: Int) {
            let myIdx = orderedNodes.count
            node.idx = myIdx
            orderedNodes.append(node)
            parentIndices.append(parentIdx)
            photoStarts.append(orderedPhotos.count)

            let sortedPhotos = node.photos.sorted { $0.name < $1.name }
            orderedPhotos.append(contentsOf: sortedPhotos)
            photoCounts.append(sortedPhotos.count)

            let sortedKeys = node.children.keys.sorted()
            for k in sortedKeys {
                if let child = node.children[k] {
                    dfs(child, parentIdx: myIdx)
                }
            }
        }

        dfs(root, parentIdx: -1)

        let n = orderedNodes.count
        var subtreeTotals = photoCounts
        for i in stride(from: n - 1, through: 1, by: -1) {
            let p = parentIndices[i]
            if p >= 0 {
                subtreeTotals[p] += subtreeTotals[i]
            }
        }

        var foldersArr: [[Any]] = []
        foldersArr.reserveCapacity(n)
        for i in 0..<n {
            foldersArr.append([
                parentIndices[i],
                orderedNodes[i].name,
                photoStarts[i],
                photoCounts[i],
                subtreeTotals[i]
            ])
        }

        let photoNames = orderedPhotos.map { $0.name }

        lock.lock()
        let nextVer = _version + 1
        let rootObj: [String: Any] = [
            "root": albumTitle,
            "rootName": rootNameLabel,
            "mode": mode,
            "version": nextVer,
            "folders": foldersArr,
            "photos": photoNames
        ]
        let jsonData = try? JSONSerialization.data(withJSONObject: rootObj, options: [])
        self.photos = orderedPhotos
        self.treeJsonData = jsonData
        self._version = nextVer
        self._scanning = false
        lock.unlock()
    }
}
