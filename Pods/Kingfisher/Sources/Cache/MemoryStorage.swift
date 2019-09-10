//
//  MemoryStorage.swift
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

// 内存缓存，这里用enum作为名字空间，具体的设置在Backend
public enum MemoryStorage {

    /**
     用来表示存储了内存中的一个具体类型的后台存储类；提供了快速存取但是存储空间有限制；
     可以通过MemoryStorage.Config来初始化，或者初始化后再设置也可以
     被存储的对象一定要遵守CacheCostCalculable协议，它的cacheCost会用来计算缓存项目的大小
     MemoryStorage也包含了一个清理任务，会清理过期的缓存
     */
    public class Backend<T: CacheCostCalculable> {
        
        // NSCache是一个可变集合，可以用来临时存储键值对；在资源不足时可能会被清除
        let storage = NSCache<NSString, StorageObject<T>>()

        /**
           用来更总缓存对象的键集合；由用户触发的移除操作，会移除相应的键；但是，由于系统的缓存规则/策略而移除对象
           相应的键并不会移除，直到下次 'removeExpired'发生
           Breaking the strict tracking could save additional locking behaviors.
           See https://github.com/onevcat/Kingfisher/issues/1233
        */
        var keys = Set<String>()

        private var cleanTimer: Timer? = nil
        private let lock = NSLock()

        // Config用来存储缓存空间大小，缓存项目个数限制，以及清理过期项目的时间间隔等
        public var config: Config {
            didSet {
                storage.totalCostLimit = config.totalCostLimit
                storage.countLimit = config.countLimit
            }
        }

        public init(config: Config) {
            self.config = config
            storage.totalCostLimit = config.totalCostLimit
            storage.countLimit = config.countLimit

            // 定义清理过期项目的定时器
            cleanTimer = .scheduledTimer(withTimeInterval: config.cleanInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.removeExpired()
            }
        }

        func removeExpired() {
            lock.lock()
            defer { lock.unlock() }
            for key in keys {
                let nsKey = key as NSString
                
                // 当缓存对象是由于系统的缓存策略，比如空间限制，项目数量限制，而被移除的时候，它的key并不会立刻被移除
                guard let object = storage.object(forKey: nsKey) else {
                    // This could happen if the object is moved by cache `totalCostLimit` or `countLimit` rule.
                    // We didn't remove the key yet until now, since we do not want to introduce additonal lock.
                    // See https://github.com/onevcat/Kingfisher/issues/1233
                    keys.remove(key)
                    continue
                }
                if object.estimatedExpiration.isPast {
                    storage.removeObject(forKey: nsKey)
                    keys.remove(key)
                }
            }
        }

        // 缓存到内存不会抛出异常，这里throw只是为了配合协议
        func store(
            value: T,
            forKey key: String,
            expiration: StorageExpiration? = nil) throws
        {
            storeNoThrow(value: value, forKey: key, expiration: expiration)
        }

        // 内部使用，不会抛出异常的缓存
        func storeNoThrow(
            value: T,
            forKey key: String,
            expiration: StorageExpiration? = nil)
        {
            lock.lock()
            defer { lock.unlock() }
            let expiration = expiration ?? config.expiration
            
            // 已经过期的话，直接返回
            guard !expiration.isExpired else { return }
            
            let object = StorageObject(value, key: key, expiration: expiration)
            
            // 将对象缓存到NSCache，并保留key
            storage.setObject(object, forKey: key as NSString, cost: value.cacheCost)
            keys.insert(key)
        }
        
        // 获取缓存对象；默认情况下，该操作会将缓存对象的过期时间延期
        // 这里默认使用原来的过期策略，并重新从当前时间计算过期时间
        func value(forKey key: String, extendingExpiration: ExpirationExtending = .cacheTime) -> T? {
            guard let object = storage.object(forKey: key as NSString) else {
                return nil
            }
            if object.expired {
                return nil
            }
            
            // extendExpiration重新计算过期时间
            object.extendExpiration(extendingExpiration)
            return object.value
        }

        func isCached(forKey key: String) -> Bool {
            guard let _ = value(forKey: key, extendingExpiration: .none) else {
                return false
            }
            return true
        }

        func remove(forKey key: String) throws {
            lock.lock()
            defer { lock.unlock() }
            storage.removeObject(forKey: key as NSString)
            keys.remove(key)
        }

        func removeAll() throws {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAllObjects()
            keys.removeAll()
        }
    }
}

extension MemoryStorage {
    //  `MemoryStorage` 用的 Config
    public struct Config {

        public var totalCostLimit: Int // 总的缓存字节数限制

        public var countLimit: Int = .max // 内存缓存的最大项目数

        public var expiration: StorageExpiration = .seconds(300) // 默认的缓存过期策略，.seconds(300)，也就是5分钟后过期

        public let cleanInterval: TimeInterval // 清理过期项目的时间间隔

        public init(totalCostLimit: Int, cleanInterval: TimeInterval = 120) {
            self.totalCostLimit = totalCostLimit
            self.cleanInterval = cleanInterval
        }
    }
}

extension MemoryStorage {
    
    // StorageObject用来约束缓存对象
    class StorageObject<T> {
        let value: T // 缓存对象的值
        let expiration: StorageExpiration // 缓存过期时间
        let key: String // 缓存对应的key
        
        private(set) var estimatedExpiration: Date // 预计的过期日期
        
        init(_ value: T, key: String, expiration: StorageExpiration) {
            self.value = value
            self.key = key
            self.expiration = expiration
            
            self.estimatedExpiration = expiration.estimatedExpirationSinceNow
        }

        // 过期时间延期设置
        func extendExpiration(_ extendingExpiration: ExpirationExtending = .cacheTime) {
            switch extendingExpiration {
            case .none: // 还是沿用原来的过期时间
                return
            case .cacheTime: // 根据原来的缓存过期策略，从当前时间开始重新计算过期时间
                self.estimatedExpiration = expiration.estimatedExpirationSinceNow
            case .expirationTime(let expirationTime): // 根据新的缓存过期策略，从当前时间重新开始计算过期时间
                self.estimatedExpiration = expirationTime.estimatedExpirationSinceNow
            }
        }
        
        var expired: Bool {
            return estimatedExpiration.isPast
        }
    }
}
