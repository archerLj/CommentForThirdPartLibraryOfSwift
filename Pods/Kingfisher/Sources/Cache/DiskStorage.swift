//
//  DiskStorage.swift
//  Kingfisher
//
//  Created by Wei Wang on 2018/10/15.
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

import Foundation


// 硬盘存储名字空间
public enum DiskStorage {

    /**
     DiskStorage的后台存储，这里的值都是序列化成data，并作为文件存储在指定的地方，所以这里的范型类必须遵守DataTransformable协议
     DiskStorage.Backend和MemoryStorage一样，也是通过Config来配置
     DiskStorage会使用文件的属性来跟踪文件是否过期或者大小限制
     */
    public class Backend<T: DataTransformable> {
        
        public var config: Config // disk storage用config

        public let directoryURL: URL // 最终在硬盘上的存储URL，根据 'name'和'cachePathBlock'决定

        let metaChangingQueue: DispatchQueue

        public init(config: Config) throws {

            self.config = config

            let url: URL
            if let directory = config.directory {
                url = directory
            } else {
                url = try config.fileManager.url(
                    for: .cachesDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true)
            }

            let cacheName = "com.onevcat.Kingfisher.ImageCache.\(config.name)"
            directoryURL = config.cachePathBlock(url, cacheName)

            metaChangingQueue = DispatchQueue(label: cacheName)

            try prepareDirectory()
        }

        // 创建硬盘缓存文件夹
        func prepareDirectory() throws {
            let fileManager = config.fileManager
            let path = directoryURL.path

            guard !fileManager.fileExists(atPath: path) else { return }

            do {
                try fileManager.createDirectory(
                    atPath: path,
                    withIntermediateDirectories: true,
                    attributes: nil)
            } catch {
                throw KingfisherError.cacheError(reason: .cannotCreateDirectory(path: path, error: error))
            }
        }

        func store(
            value: T,
            forKey key: String,
            expiration: StorageExpiration? = nil) throws
        {
            let expiration = expiration ?? config.expiration
            // The expiration indicates that already expired, no need to store.
            guard !expiration.isExpired else { return }
            
            let data: Data
            do {
                data = try value.toData()
            } catch {
                throw KingfisherError.cacheError(reason: .cannotConvertToData(object: value, error: error))
            }

            let fileURL = cacheFileURL(forKey: key)

            let now = Date()
            let attributes: [FileAttributeKey : Any] = [
                // The last access date.
                .creationDate: now.fileAttributeDate,
                // The estimated expiration date.
                .modificationDate: expiration.estimatedExpirationSinceNow.fileAttributeDate
            ]
            config.fileManager.createFile(atPath: fileURL.path, contents: data, attributes: attributes)
        }

        func value(forKey key: String) throws -> T? {
            return try value(forKey: key, referenceDate: Date(), actuallyLoad: true)
        }

        func value(forKey key: String, referenceDate: Date, actuallyLoad: Bool) throws -> T? {
            let fileManager = config.fileManager
            let fileURL = cacheFileURL(forKey: key)
            let filePath = fileURL.path
            guard fileManager.fileExists(atPath: filePath) else {
                return nil
            }

            let meta: FileMeta
            do {
                let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
                meta = try FileMeta(fileURL: fileURL, resourceKeys: resourceKeys)
            } catch {
                throw KingfisherError.cacheError(
                    reason: .invalidURLResource(error: error, key: key, url: fileURL))
            }

            if meta.expired(referenceDate: referenceDate) {
                return nil
            }
            if !actuallyLoad { return T.empty }

            do {
                let data = try Data(contentsOf: fileURL)
                let obj = try T.fromData(data)
                metaChangingQueue.async { meta.extendExpiration(with: fileManager) }
                return obj
            } catch {
                throw KingfisherError.cacheError(reason: .cannotLoadDataFromDisk(url: fileURL, error: error))
            }
        }

        func isCached(forKey key: String) -> Bool {
            return isCached(forKey: key, referenceDate: Date())
        }

        func isCached(forKey key: String, referenceDate: Date) -> Bool {
            do {
                guard let _ = try value(forKey: key, referenceDate: referenceDate, actuallyLoad: false) else {
                    return false
                }
                return true
            } catch {
                return false
            }
        }

        func remove(forKey key: String) throws {
            let fileURL = cacheFileURL(forKey: key)
            try removeFile(at: fileURL)
        }

        // 直接使用FileManager移除文件或者目录
        func removeFile(at url: URL) throws {
            try config.fileManager.removeItem(at: url)
        }

        func removeAll() throws {
            try removeAll(skipCreatingDirectory: false)
        }

        func removeAll(skipCreatingDirectory: Bool) throws {
            try config.fileManager.removeItem(at: directoryURL)
            if !skipCreatingDirectory {
                try prepareDirectory()
            }
        }

        // 根据指定的key，返回应该存储在硬盘的URL
        public func cacheFileURL(forKey key: String) -> URL {
            let fileName = cacheFileName(forKey: key)
            return directoryURL.appendingPathComponent(fileName)
        }

        // 获取缓存文件名称，如果配置里有扩展名，则包括扩展名
        func cacheFileName(forKey key: String) -> String {
            
            if config.usesHashedFileName {
                // String类型也遵守了KingfisherWrap协议，所以它也有在名字空间kf内
                let hashedKey = key.kf.md5
                if let ext = config.pathExtension {
                    return "\(hashedKey).\(ext)"
                }
                return hashedKey
            } else {
                if let ext = config.pathExtension {
                    return "\(key).\(ext)"
                }
                return key
            }
        }

        // 根据指定的文件属性key获取缓存目录的所有文件URL
        func allFileURLs(for propertyKeys: [URLResourceKey]) throws -> [URL] {
            let fileManager = config.fileManager

            // 创建一个目录遍历器
            guard let directoryEnumerator = fileManager.enumerator(
                at: directoryURL, includingPropertiesForKeys: propertyKeys, options: .skipsHiddenFiles) else
            {
                throw KingfisherError.cacheError(reason: .fileEnumeratorCreationFailed(url: directoryURL))
            }

            guard let urls = directoryEnumerator.allObjects as? [URL] else {
                throw KingfisherError.cacheError(reason: .invalidFileEnumeratorContent(url: directoryURL))
            }
            return urls
        }

        // 移除过期的文件
        func removeExpiredValues(referenceDate: Date = Date()) throws -> [URL] {
            let propertyKeys: [URLResourceKey] = [
                .isDirectoryKey, // 表示是否是目录
                .contentModificationDateKey // 文件最近更改的时间
            ]

            let urls = try allFileURLs(for: propertyKeys)
            let keys = Set(propertyKeys)
            let expiredFiles = urls.filter { fileURL in
                do {
                    // 获取文件的一些基本信息
                    let meta = try FileMeta(fileURL: fileURL, resourceKeys: keys)
                    if meta.isDirectory {
                        return false
                    }
                    // 判断文件是否过期，这里默认是和当前时间比较
                    return meta.expired(referenceDate: referenceDate)
                } catch {
                    return true
                }
            }
            
            try expiredFiles.forEach { url in
                try removeFile(at: url)
            }
            return expiredFiles
        }

        // 移除大小超过限制的文件
        func removeSizeExceededValues() throws -> [URL] {

            if config.sizeLimit == 0 { return [] } // sizeLimit=0表示没有限制

            var size = try totalSize()
            if size < config.sizeLimit { return [] }

            let propertyKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .creationDateKey,
                .fileSizeKey
            ]
            let keys = Set(propertyKeys)

            let urls = try allFileURLs(for: propertyKeys)
            
            // compactMap会将nil排除在外, compact：紧凑的
            var pendings: [FileMeta] = urls.compactMap { fileURL in
                guard let meta = try? FileMeta(fileURL: fileURL, resourceKeys: keys) else {
                    return nil
                }
                return meta
            }
            
            // 对文件进行排序；lastAccessDate方法定义了文件日期比较的规则
            pendings.sort(by: FileMeta.lastAccessDate)

            var removed: [URL] = []
            
            // 将缓存大小降到指定缓存大小的一半
            let target = config.sizeLimit / 2
            while size > target, let meta = pendings.popLast() {
                size -= UInt(meta.fileSize)
                try removeFile(at: meta.url)
                removed.append(meta.url)
            }
            return removed
        }

        // 获取缓存的文件的总大小，单位是byte
        func totalSize() throws -> UInt {
            let propertyKeys: [URLResourceKey] = [.fileSizeKey]
            let urls = try allFileURLs(for: propertyKeys)
            let keys = Set(propertyKeys)
            let totalSize: UInt = urls.reduce(0) { size, fileURL in
                do {
                    let meta = try FileMeta(fileURL: fileURL, resourceKeys: keys)
                    return size + UInt(meta.fileSize)
                } catch {
                    return size
                }
            }
            return totalSize
        }
    }
}

extension DiskStorage {
    
    public struct Config {

        public var sizeLimit: UInt // 存储在硬盘上的文件大小限制，单位是byte，0表示没有限制

        public var expiration: StorageExpiration = .days(7) // 硬盘缓存的过期策略，默认是.days(7)，也就是默认保存一周

        public var pathExtension: String? = nil // 文件名后缀，默认没有扩展名

        public var usesHashedFileName = true // 默认在存储之前会将文件名哈希化

        let name: String
        let fileManager: FileManager
        let directory: URL?

        var cachePathBlock: ((_ directory: URL, _ cacheName: String) -> URL)! = {
            (directory, cacheName) in
            return directory.appendingPathComponent(cacheName, isDirectory: true)
        }

        public init(
            name: String,
            sizeLimit: UInt,
            fileManager: FileManager = .default,
            directory: URL? = nil)
        {
            self.name = name
            self.fileManager = fileManager
            self.directory = directory
            self.sizeLimit = sizeLimit
        }
    }
}

extension DiskStorage {
    
    // 获取文件的创建时间，最近修改时间等
    // 设置新的过期时间等等操作
    struct FileMeta {
    
        let url: URL
        
        let lastAccessDate: Date?
        let estimatedExpirationDate: Date?
        let isDirectory: Bool
        let fileSize: Int
        
        static func lastAccessDate(lhs: FileMeta, rhs: FileMeta) -> Bool {
            return lhs.lastAccessDate ?? .distantPast > rhs.lastAccessDate ?? .distantPast
        }
        
        init(fileURL: URL, resourceKeys: Set<URLResourceKey>) throws {
            let meta = try fileURL.resourceValues(forKeys: resourceKeys)
            self.init(
                fileURL: fileURL,
                lastAccessDate: meta.creationDate,
                estimatedExpirationDate: meta.contentModificationDate,
                isDirectory: meta.isDirectory ?? false,
                fileSize: meta.fileSize ?? 0)
        }
        
        init(
            fileURL: URL,
            lastAccessDate: Date?,
            estimatedExpirationDate: Date?,
            isDirectory: Bool,
            fileSize: Int)
        {
            self.url = fileURL
            self.lastAccessDate = lastAccessDate
            self.estimatedExpirationDate = estimatedExpirationDate
            self.isDirectory = isDirectory
            self.fileSize = fileSize
        }

        func expired(referenceDate: Date) -> Bool {
            return estimatedExpirationDate?.isPast(referenceDate: referenceDate) ?? true
        }
        
        func extendExpiration(with fileManager: FileManager) {
            guard let lastAccessDate = lastAccessDate,
                  let lastEstimatedExpiration = estimatedExpirationDate else
            {
                return
            }
            
            let originalExpiration: StorageExpiration =
                .seconds(lastEstimatedExpiration.timeIntervalSince(lastAccessDate))
            let attributes: [FileAttributeKey : Any] = [
                .creationDate: Date().fileAttributeDate, // fileAttributeDate会对日期做向上取整
                .modificationDate: originalExpiration.estimatedExpirationSinceNow.fileAttributeDate
            ]

            try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        }
    }
}

