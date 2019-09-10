//
//  ImageCache.swift
//  Kingfisher
//
//  Created by Wei Wang on 15/4/6.
//
//  Copyright (c) 2019 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

/**
  负责将加载过的图片缓存至本地
 */

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Notification.Name {
    /// This notification will be sent when the disk cache got cleaned either there are cached files expired or the
    /// total size exceeding the max allowed size. The manually invoking of `clearDiskCache` method will not trigger
    /// this notification.
    ///
    /// The `object` of this notification is the `ImageCache` object which sends the notification.
    /// A list of removed hashes (files) could be retrieved by accessing the array under
    /// `KingfisherDiskCacheCleanedHashKey` key in `userInfo` of the notification object you received.
    /// By checking the array, you could know the hash codes of files are removed.
    
    // 这里手动调用clearDiskCache不会触发通知
    public static let KingfisherDidCleanDiskCache =
        Notification.Name("com.onevcat.Kingfisher.KingfisherDidCleanDiskCache")
}

// 这个Key用来表示 KingfisherDidCleanDiskCache通知的userInfo中被包含的移除文件的哈希值
public let KingfisherDiskCacheCleanedHashKey = "com.onevcat.Kingfisher.cleanedHash"

// 缓存类型
public enum CacheType {

    case none // 不做缓存
    
    case memory // 缓存在内存中
    
    case disk // 缓存在硬盘中
    
    // 判断图片是否被缓存了
    public var cached: Bool {
        switch self {
        case .memory, .disk: return true
        case .none: return false
        }
    }
}

// 缓存的结果
public struct CacheStoreResult {
    
    // 缓存到内存中永远都不会失败，所以swift Result类型的第二个参数使用Never表示永远不会发生
    // 关于Never可以看这里：https://swift.gg/2018/08/30/never/
    public let memoryCacheResult: Result<(), Never>
    
    // 缓存到硬盘的结果，如果缓存失败，可以用.failure(let error)获取到一个KingfisherError的错误结果
    public let diskCacheResult: Result<(), KingfisherError>
}

// CacheCostCalculable是一个计算内存占用的协议
extension Image: CacheCostCalculable {
    // 获取图片占用的内存byte数
    public var cacheCost: Int { return kf.cost }
}

// DataTransformable表示可以转为Data，以及可以从Data转回来的类型
extension Data: DataTransformable {
    public func toData() throws -> Data {
        return self
    }

    public static func fromData(_ data: Data) throws -> Data {
        return data
    }

    public static let empty = Data()
}


// 代表从缓存取回图片的操作
public enum ImageCacheResult {
    
    case disk(Image) // 表示图片可以从硬盘取回
    
    case memory(Image) // 表示图片可以从内存取回
    
    case none // 图片在缓存中不存在
    
    // 从缓存结果中提取图片
    public var image: Image? {
        switch self {
        case .disk(let image): return image
        case .memory(let image): return image
        case .none: return nil
        }
    }
    
    // 返回对应的缓存类型
    public var cacheType: CacheType {
        switch self {
        case .disk: return .disk
        case .memory: return .memory
        case .none: return .none
        }
    }
}

/***
 ImageCache是一个混合的，高层次抽象的图片缓存和取回系统，它里面结合了 MemoryStorage.Backend和DiskStorage.Backend
 
 Kingfisher提供了默认的缓存实现，同样它也提供了对应的接口，你可以根据接口来实现自己的缓存
 */
open class ImageCache {

    // 单例
    // 默认的图片缓存对象，如果默认缓存的名字叫"default"，如果你是自定义缓存的话，不要使用这个名字
    public static let `default` = ImageCache(name: "default")

    // memoryStorage持有内存中所有加载的图片，包括过期时长以及最大内存大小，如果要修改存储的配置，直接设置它的config和属性即可
    public let memoryStorage: MemoryStorage.Backend<Image>
    
    // diskStorage用来加载硬盘上缓存的图片，也可以设置它的config和属性
    public let diskStorage: DiskStorage.Backend<Data>
    
    private let ioQueue: DispatchQueue
    
    // 根据给定的url和缓存名称取得在硬盘中缓存的路径
    public typealias DiskCachePathClosure = (URL, String) -> URL

    // MARK: Initializers

    // 从自定义的MemoryStorage和DiskStorage初始化图片缓存
    public init(
        memoryStorage: MemoryStorage.Backend<Image>,
        diskStorage: DiskStorage.Backend<Data>)
    {
        self.memoryStorage = memoryStorage
        self.diskStorage = diskStorage
        let ioQueueName = "com.onevcat.Kingfisher.ImageCache.ioQueue.\(UUID().uuidString)"
        ioQueue = DispatchQueue(label: ioQueueName)

        // notifications用来存储一些系统的通知，具体在下面
        let notifications: [(Notification.Name, Selector)]
        #if !os(macOS) && !os(watchOS)
        #if swift(>=4.2)
        notifications = [
            (UIApplication.didReceiveMemoryWarningNotification, #selector(clearMemoryCache)), // 接收到内存警告，清空内存缓存
            (UIApplication.willTerminateNotification, #selector(cleanExpiredDiskCache)), // 接收到应用终止通知，清除过期硬盘缓存
            (UIApplication.didEnterBackgroundNotification, #selector(backgroundCleanExpiredDiskCache)) // 进入后台通知，后台清除过期硬盘缓存
        ]
        #else
        notifications = [
            (NSNotification.Name.UIApplicationDidReceiveMemoryWarning, #selector(clearMemoryCache)),
            (NSNotification.Name.UIApplicationWillTerminate, #selector(cleanExpiredDiskCache)),
            (NSNotification.Name.UIApplicationDidEnterBackground, #selector(backgroundCleanExpiredDiskCache))
        ]
        #endif
        #elseif os(macOS)
        notifications = [
            (NSApplication.willResignActiveNotification, #selector(cleanExpiredDiskCache)),
        ]
        #else
        notifications = []
        #endif
        
        // 依次添加对应的通知和处理方法
        notifications.forEach {
            NotificationCenter.default.addObserver(self, selector: $0.1, name: $0.0, object: nil)
        }
    }
    
    public convenience init(name: String) {
        try! self.init(name: name, cacheDirectoryURL: nil, diskCachePathClosure: nil)
    }
    
    // diskCachePathClosure是用来组装最终硬盘缓存路径的block
    public convenience init(
        name: String,
        cacheDirectoryURL: URL?,
        diskCachePathClosure: DiskCachePathClosure? = nil) throws
    {
        if name.isEmpty {
            fatalError("[Kingfisher] You should specify a name for the cache. A cache with empty name is not permitted.")
        }

        let totalMemory = ProcessInfo.processInfo.physicalMemory // 获取当前进程的存储空间
        let costLimit = totalMemory / 4
        let memoryStorage = MemoryStorage.Backend<Image>(config:
            .init(totalCostLimit: (costLimit > Int.max) ? Int.max : Int(costLimit)))

        var diskConfig = DiskStorage.Config(
            name: name,
            sizeLimit: 0,
            directory: cacheDirectoryURL
        )
        if let closure = diskCachePathClosure {
            diskConfig.cachePathBlock = closure
        }
        let diskStorage = try DiskStorage.Backend<Data>(config: diskConfig)
        diskConfig.cachePathBlock = nil

        self.init(memoryStorage: memoryStorage, diskStorage: diskStorage)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // 存储图片
    open func store(_ image: Image,
                    original: Data? = nil,
                    forKey key: String,
                    options: KingfisherParsedOptionsInfo,
                    toDisk: Bool = true,
                    completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        let identifier = options.processor.identifier
        let callbackQueue = options.callbackQueue
        
        let computedKey = key.computedKey(with: identifier)
        // Memory storage should not throw.
        memoryStorage.storeNoThrow(value: image, forKey: computedKey, expiration: options.memoryCacheExpiration)
        
        guard toDisk else {
            if let completionHandler = completionHandler {
                let result = CacheStoreResult(memoryCacheResult: .success(()), diskCacheResult: .success(()))
                callbackQueue.execute { completionHandler(result) }
            }
            return
        }
        
        ioQueue.async {
            let serializer = options.cacheSerializer
            if let data = serializer.data(with: image, original: original) {
                self.syncStoreToDisk(
                    data,
                    forKey: key,
                    processorIdentifier: identifier,
                    callbackQueue: callbackQueue,
                    expiration: options.diskCacheExpiration,
                    completionHandler: completionHandler)
            } else {
                guard let completionHandler = completionHandler else { return }
                
                let diskError = KingfisherError.cacheError(
                    reason: .cannotSerializeImage(image: image, original: original, serializer: serializer))
                let result = CacheStoreResult(
                    memoryCacheResult: .success(()),
                    diskCacheResult: .failure(diskError))
                callbackQueue.execute { completionHandler(result) }
            }
        }
    }

    /// Stores an image to the cache.
    ///
    /// - Parameters:
    ///   - image: The image to be stored.
    ///   - original: The original data of the image. This value will be forwarded to the provided `serializer` for
    ///               further use. By default, Kingfisher uses a `DefaultCacheSerializer` to serialize the image to
    ///               data for caching in disk, it checks the image format based on `original` data to determine in
    ///               which image format should be used. For other types of `serializer`, it depends on their
    ///               implementation detail on how to use this original data.
    ///   - key: The key used for caching the image.
    ///   - identifier: The identifier of processor being used for caching. If you are using a processor for the
    ///                 image, pass the identifier of processor to this parameter.
    ///   - serializer: The `CacheSerializer`
    ///   - toDisk: Whether this image should be cached to disk or not. If `false`, the image is only cached in memory.
    ///             Otherwise, it is cached in both memory storage and disk storage. Default is `true`.
    ///   - callbackQueue: The callback queue on which `completionHandler` is invoked. Default is `.untouch`. For case
    ///                    that `toDisk` is `false`, a `.untouch` queue means `callbackQueue` will be invoked from the
    ///                    caller queue of this method. If `toDisk` is `true`, the `completionHandler` will be called
    ///                    from an internal file IO queue. To change this behavior, specify another `CallbackQueue`
    ///                    value.
    ///   - completionHandler: A closure which is invoked when the cache operation finishes.
    open func store(_ image: Image,
                      original: Data? = nil,
                      forKey key: String,
                      processorIdentifier identifier: String = "",
                      cacheSerializer serializer: CacheSerializer = DefaultCacheSerializer.default,
                      toDisk: Bool = true,
                      callbackQueue: CallbackQueue = .untouch,
                      completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        struct TempProcessor: ImageProcessor {
            let identifier: String
            func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> Image? {
                return nil
            }
        }
        
        let options = KingfisherParsedOptionsInfo([
            .processor(TempProcessor(identifier: identifier)),
            .cacheSerializer(serializer),
            .callbackQueue(callbackQueue)
        ])
        store(image, original: original, forKey: key, options: options,
              toDisk: toDisk, completionHandler: completionHandler)
    }
    
    open func storeToDisk(
        _ data: Data,
        forKey key: String,
        processorIdentifier identifier: String = "",
        expiration: StorageExpiration? = nil,
        callbackQueue: CallbackQueue = .untouch,
        completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        ioQueue.async {
            self.syncStoreToDisk(
                data,
                forKey: key,
                processorIdentifier: identifier,
                callbackQueue: callbackQueue,
                expiration: expiration,
                completionHandler: completionHandler)
        }
    }
    
    private func syncStoreToDisk(
        _ data: Data,
        forKey key: String,
        processorIdentifier identifier: String = "",
        callbackQueue: CallbackQueue = .untouch,
        expiration: StorageExpiration? = nil,
        completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        let computedKey = key.computedKey(with: identifier)
        let result: CacheStoreResult
        do {
            try self.diskStorage.store(value: data, forKey: computedKey, expiration: expiration)
            result = CacheStoreResult(memoryCacheResult: .success(()), diskCacheResult: .success(()))
        } catch {
            let diskError: KingfisherError
            if let error = error as? KingfisherError {
                diskError = error
            } else {
                diskError = .cacheError(reason: .cannotConvertToData(object: data, error: error))
            }
            
            result = CacheStoreResult(
                memoryCacheResult: .success(()),
                diskCacheResult: .failure(diskError)
            )
        }
        if let completionHandler = completionHandler {
            callbackQueue.execute { completionHandler(result) }
        }
    }

    // MARK: Removing Images

    /// Removes the image for the given key from the cache.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: The identifier of processor being used for caching. If you are using a processor for the
    ///                 image, pass the identifier of processor to this parameter.
    ///   - fromMemory: Whether this image should be removed from memory storage or not.
    ///                 If `false`, the image won't be removed from the memory storage. Default is `true`.
    ///   - fromDisk: Whether this image should be removed from disk storage or not.
    ///               If `false`, the image won't be removed from the disk storage. Default is `true`.
    ///   - callbackQueue: The callback queue on which `completionHandler` is invoked. Default is `.untouch`.
    ///   - completionHandler: A closure which is invoked when the cache removing operation finishes.
    open func removeImage(forKey key: String,
                          processorIdentifier identifier: String = "",
                          fromMemory: Bool = true,
                          fromDisk: Bool = true,
                          callbackQueue: CallbackQueue = .untouch,
                          completionHandler: (() -> Void)? = nil)
    {
        let computedKey = key.computedKey(with: identifier)

        if fromMemory {
            try? memoryStorage.remove(forKey: computedKey)
        }
        
        if fromDisk {
            ioQueue.async{
                try? self.diskStorage.remove(forKey: computedKey)
                if let completionHandler = completionHandler {
                    callbackQueue.execute { completionHandler() }
                }
            }
        } else {
            if let completionHandler = completionHandler {
                callbackQueue.execute { completionHandler() }
            }
        }
    }

    func retrieveImage(forKey key: String,
                       options: KingfisherParsedOptionsInfo,
                       callbackQueue: CallbackQueue = .untouch,
                       completionHandler: ((Result<ImageCacheResult, KingfisherError>) -> Void)?)
    {
        // No completion handler. No need to start working and early return.
        guard let completionHandler = completionHandler else { return }

        // Try to check the image from memory cache first.
        if let image = retrieveImageInMemoryCache(forKey: key, options: options) {
            let image = options.imageModifier?.modify(image) ?? image
            callbackQueue.execute { completionHandler(.success(.memory(image))) }
        } else if options.fromMemoryCacheOrRefresh {
            callbackQueue.execute { completionHandler(.success(.none)) }
        } else {
            // Begin to disk search.
            self.retrieveImageInDiskCache(forKey: key, options: options, callbackQueue: callbackQueue) {
                result in
                // The callback queue is already correct in this closure.
                switch result {
                case .success(let image):

                    guard let image = image else {
                        // No image found in disk storage.
                        completionHandler(.success(.none))
                        return
                    }

                    let finalImage = options.imageModifier?.modify(image) ?? image
                    // Cache the disk image to memory.
                    // We are passing `false` to `toDisk`, the memory cache does not change
                    // callback queue, we can call `completionHandler` without another dispatch.
                    var cacheOptions = options
                    cacheOptions.callbackQueue = .untouch
                    self.store(
                        finalImage,
                        forKey: key,
                        options: cacheOptions,
                        toDisk: false)
                    {
                        _ in
                        completionHandler(.success(.disk(finalImage)))
                    }
                case .failure(let error):
                    completionHandler(.failure(error))
                }
            }
        }
    }

    // MARK: Getting Images

    /// Gets an image for a given key from the cache, either from memory storage or disk storage.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - options: The `KingfisherOptionsInfo` options setting used for retrieving the image.
    ///   - callbackQueue: The callback queue on which `completionHandler` is invoked. Default is `.untouch`.
    ///   - completionHandler: A closure which is invoked when the image getting operation finishes. If the
    ///                        image retrieving operation finishes without problem, an `ImageCacheResult` value
    ///                        will be sent to this closure as result. Otherwise, a `KingfisherError` result
    ///                        with detail failing reason will be sent.
    open func retrieveImage(forKey key: String,
                               options: KingfisherOptionsInfo? = nil,
                        callbackQueue: CallbackQueue = .untouch,
                     completionHandler: ((Result<ImageCacheResult, KingfisherError>) -> Void)?)
    {
        retrieveImage(
            forKey: key,
            options: KingfisherParsedOptionsInfo(options),
            callbackQueue: callbackQueue,
            completionHandler: completionHandler)
    }

    func retrieveImageInMemoryCache(
        forKey key: String,
        options: KingfisherParsedOptionsInfo) -> Image?
    {
        let computedKey = key.computedKey(with: options.processor.identifier)
        return memoryStorage.value(forKey: computedKey, extendingExpiration: options.memoryCacheAccessExtendingExpiration)
    }

    /// Gets an image for a given key from the memory storage.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - options: The `KingfisherOptionsInfo` options setting used for retrieving the image.
    /// - Returns: The image stored in memory cache, if exists and valid. Otherwise, if the image does not exist or
    ///            has already expired, `nil` is returned.
    open func retrieveImageInMemoryCache(
        forKey key: String,
        options: KingfisherOptionsInfo? = nil) -> Image?
    {
        return retrieveImageInMemoryCache(forKey: key, options: KingfisherParsedOptionsInfo(options))
    }

    func retrieveImageInDiskCache(
        forKey key: String,
        options: KingfisherParsedOptionsInfo,
        callbackQueue: CallbackQueue = .untouch,
        completionHandler: @escaping (Result<Image?, KingfisherError>) -> Void)
    {
        let computedKey = key.computedKey(with: options.processor.identifier)
        let loadingQueue: CallbackQueue = options.loadDiskFileSynchronously ? .untouch : .dispatch(ioQueue)
        loadingQueue.execute {
            do {
                var image: Image? = nil
                if let data = try self.diskStorage.value(forKey: computedKey) {
                    image = options.cacheSerializer.image(with: data, options: options)
                }
                callbackQueue.execute { completionHandler(.success(image)) }
            } catch {
                if let error = error as? KingfisherError {
                    callbackQueue.execute { completionHandler(.failure(error)) }
                } else {
                    assertionFailure("The internal thrown error should be a `KingfisherError`.")
                }
            }
        }
    }
    
    /// Gets an image for a given key from the disk storage.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - options: The `KingfisherOptionsInfo` options setting used for retrieving the image.
    ///   - callbackQueue: The callback queue on which `completionHandler` is invoked. Default is `.untouch`.
    ///   - completionHandler: A closure which is invoked when the operation finishes.
    open func retrieveImageInDiskCache(
        forKey key: String,
        options: KingfisherOptionsInfo? = nil,
        callbackQueue: CallbackQueue = .untouch,
        completionHandler: @escaping (Result<Image?, KingfisherError>) -> Void)
    {
        retrieveImageInDiskCache(
            forKey: key,
            options: KingfisherParsedOptionsInfo(options),
            callbackQueue: callbackQueue,
            completionHandler: completionHandler)
    }

    // 清空内存缓存
    @objc public func clearMemoryCache() {
        try? memoryStorage.removeAll()
    }
    
    /// Clears the disk storage of this cache. This is an async operation.
    ///
    /// - Parameter handler: A closure which is invoked when the cache clearing operation finishes.
    ///                      This `handler` will be called from the main queue.
    open func clearDiskCache(completion handler: (()->())? = nil) {
        ioQueue.async {
            do {
                try self.diskStorage.removeAll()
            } catch _ { }
            if let handler = handler {
                DispatchQueue.main.async { handler() }
            }
        }
    }

    /// Clears the expired images from disk storage. This is an async operation.
    open func cleanExpiredMemoryCache() {
        memoryStorage.removeExpired()
    }
    
    // 清理过期的硬盘缓存，这是异步操作
    @objc func cleanExpiredDiskCache() {
        cleanExpiredDiskCache(completion: nil)
    }

    // 清理过期的硬盘缓存，这是异步操作
    open func cleanExpiredDiskCache(completion handler: (() -> Void)? = nil) {
        ioQueue.async {
            do {
                var removed: [URL] = []
                let removedExpired = try self.diskStorage.removeExpiredValues()
                removed.append(contentsOf: removedExpired)

                let removedSizeExceeded = try self.diskStorage.removeSizeExceededValues()
                removed.append(contentsOf: removedSizeExceeded)

                if !removed.isEmpty {
                    DispatchQueue.main.async {
                        let cleanedHashes = removed.map { $0.lastPathComponent }
                        NotificationCenter.default.post(
                            name: .KingfisherDidCleanDiskCache,
                            object: self,
                            userInfo: [KingfisherDiskCacheCleanedHashKey: cleanedHashes])
                    }
                }

                if let handler = handler {
                    DispatchQueue.main.async { handler() }
                }
            } catch {}
        }
    }

#if !os(macOS) && !os(watchOS)
    /// Clears the expired images from disk storage when app is in background. This is an async operation.
    /// In most cases, you should not call this method explicitly.
    /// It will be called automatically when `UIApplicationDidEnterBackgroundNotification` received.
    @objc public func backgroundCleanExpiredDiskCache() {
        // if 'sharedApplication()' is unavailable, then return
        guard let sharedApplication = KingfisherWrapper<UIApplication>.shared else { return }

        func endBackgroundTask(_ task: inout UIBackgroundTaskIdentifier) {
            sharedApplication.endBackgroundTask(task)
            #if swift(>=4.2)
            task = UIBackgroundTaskIdentifier.invalid
            #else
            task = UIBackgroundTaskInvalid
            #endif
        }
        
        var backgroundTask: UIBackgroundTaskIdentifier!
        backgroundTask = sharedApplication.beginBackgroundTask {
            endBackgroundTask(&backgroundTask!)
        }
        
        cleanExpiredDiskCache {
            endBackgroundTask(&backgroundTask!)
        }
    }
#endif

    // MARK: Image Cache State

    /// Returns the cache type for a given `key` and `identifier` combination.
    /// This method is used for checking whether an image is cached in current cache.
    /// It also provides information on which kind of cache can it be found in the return value.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: A `CacheType` instance which indicates the cache status.
    ///            `.none` means the image is not in cache or it is already expired.
    open func imageCachedType(
        forKey key: String,
        processorIdentifier identifier: String = DefaultImageProcessor.default.identifier) -> CacheType
    {
        let computedKey = key.computedKey(with: identifier)
        if memoryStorage.isCached(forKey: computedKey) { return .memory }
        if diskStorage.isCached(forKey: computedKey) { return .disk }
        return .none
    }
    
    /// Returns whether the file exists in cache for a given `key` and `identifier` combination.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: A `Bool` which indicates whether a cache could match the given `key` and `identifier` combination.
    ///
    /// - Note:
    /// The return value does not contain information about from which kind of storage the cache matches.
    /// To get the information about cache type according `CacheType`,
    /// use `imageCachedType(forKey:processorIdentifier:)` instead.
    public func isCached(
        forKey key: String,
        processorIdentifier identifier: String = DefaultImageProcessor.default.identifier) -> Bool
    {
        return imageCachedType(forKey: key, processorIdentifier: identifier).cached
    }
    
    /// Gets the hash used as cache file name for the key.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: The hash which is used as the cache file name.
    ///
    /// - Note:
    /// By default, for a given combination of `key` and `identifier`, `ImageCache` will use the value
    /// returned by this method as the cache file name. You can use this value to check and match cache file
    /// if you need.
    open func hash(
        forKey key: String,
        processorIdentifier identifier: String = DefaultImageProcessor.default.identifier) -> String
    {
        let computedKey = key.computedKey(with: identifier)
        return diskStorage.cacheFileName(forKey: computedKey)
    }
    
    /// Calculates the size taken by the disk storage.
    /// It is the total file size of all cached files in the `diskStorage` on disk in bytes.
    ///
    /// - Parameter handler: Called with the size calculating finishes. This closure is invoked from the main queue.
    open func calculateDiskStorageSize(completion handler: @escaping ((Result<UInt, KingfisherError>) -> Void)) {
        ioQueue.async {
            do {
                let size = try self.diskStorage.totalSize()
                DispatchQueue.main.async { handler(.success(size)) }
            } catch {
                if let error = error as? KingfisherError {
                    DispatchQueue.main.async { handler(.failure(error)) }
                } else {
                    assertionFailure("The internal thrown error should be a `KingfisherError`.")
                }
                
            }
        }
    }
    
    /// Gets the cache path for the key.
    /// It is useful for projects with web view or anyone that needs access to the local file path.
    ///
    /// i.e. Replacing the `<img src='path_for_key'>` tag in your HTML.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: The disk path of cached image under the given `key` and `identifier`.
    ///
    /// - Note:
    /// This method does not guarantee there is an image already cached in the returned path. It just gives your
    /// the path that the image should be, if it exists in disk storage.
    ///
    /// You could use `isCached(forKey:)` method to check whether the image is cached under that key in disk.
    open func cachePath(
        forKey key: String,
        processorIdentifier identifier: String = DefaultImageProcessor.default.identifier) -> String
    {
        let computedKey = key.computedKey(with: identifier)
        return diskStorage.cacheFileURL(forKey: computedKey).path
    }
}

extension Dictionary {
    func keysSortedByValue(_ isOrderedBefore: (Value, Value) -> Bool) -> [Key] {
        return Array(self).sorted{ isOrderedBefore($0.1, $1.1) }.map{ $0.0 }
    }
}

#if !os(macOS) && !os(watchOS)
// MARK: - For App Extensions
extension UIApplication: KingfisherCompatible { }
extension KingfisherWrapper where Base: UIApplication {
    public static var shared: UIApplication? {
        let selector = NSSelectorFromString("sharedApplication")
        guard Base.responds(to: selector) else { return nil }
        return Base.perform(selector).takeUnretainedValue() as? UIApplication
    }
}
#endif

extension String {
    func computedKey(with identifier: String) -> String {
        if identifier.isEmpty {
            return self
        } else {
            return appending("@\(identifier)")
        }
    }
}

extension ImageCache {

    /// Creates an `ImageCache` with a given `name`, cache directory `path`
    /// and a closure to modify the cache directory.
    ///
    /// - Parameters:
    ///   - name: The name of cache object. It is used to setup disk cache directories and IO queue.
    ///           You should not use the same `name` for different caches, otherwise, the disk storage would
    ///           be conflicting to each other.
    ///   - path: Location of cache URL on disk. It will be internally pass to the initializer of `DiskStorage` as the
    ///           disk cache directory.
    ///   - diskCachePathClosure: Closure that takes in an optional initial path string and generates
    ///                           the final disk cache path. You could use it to fully customize your cache path.
    /// - Throws: An error that happens during image cache creating, such as unable to create a directory at the given
    ///           path.
    @available(*, deprecated, message: "Use `init(name:cacheDirectoryURL:diskCachePathClosure:)` instead",
    renamed: "init(name:cacheDirectoryURL:diskCachePathClosure:)")
    public convenience init(
        name: String,
        path: String?,
        diskCachePathClosure: DiskCachePathClosure? = nil) throws
    {
        let directoryURL = path.flatMap { URL(string: $0) }
        try self.init(name: name, cacheDirectoryURL: directoryURL, diskCachePathClosure: diskCachePathClosure)
    }
}
