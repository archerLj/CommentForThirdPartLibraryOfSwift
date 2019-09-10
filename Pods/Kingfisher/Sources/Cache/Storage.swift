//
//  Storage.swift
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

/// Constants for some time intervals
struct TimeConstants {
    static let secondsInOneMinute = 60
    static let minutesInOneHour = 60
    static let hoursInOneDay = 24
    static let secondsInOneDay = secondsInOneMinute * minutesInOneHour * hoursInOneDay
}

// 缓存过期策略
public enum StorageExpiration {
    
    case never // 从不过期
    
    case seconds(TimeInterval) // 从现在开始，在指定秒后过期
    
    case days(Int) // 从现在开始，指定天数后过期
    
    case date(Date) // 指定日期后过期
    
    case expired // 标示已经过期，跳过缓存

    // 计算从某个日期开始的过期日期
    func estimatedExpirationSince(_ date: Date) -> Date {
        switch self {
        case .never: return .distantFuture // distantFuture表示一个在遥远未来的日期对象
        case .seconds(let seconds): return date.addingTimeInterval(seconds)
        case .days(let days): return date.addingTimeInterval(TimeInterval(TimeConstants.secondsInOneDay * days))
        case .date(let ref): return ref
        case .expired: return .distantPast // distantPast表示一个已经过去的日期对象
        }
    }
    
    // 从当前日期计算过期日期
    var estimatedExpirationSinceNow: Date {
        return estimatedExpirationSince(Date())
    }
    
    var isExpired: Bool {
        return timeInterval <= 0
    }

    var timeInterval: TimeInterval {
        switch self {
        case .never: return .infinity
        case .seconds(let seconds): return seconds
        case .days(let days): return TimeInterval(TimeConstants.secondsInOneDay * days)
        case .date(let ref): return ref.timeIntervalSinceNow
        case .expired: return -(.infinity)
        }
    }
}

// 缓存对象被访问后的过期时间延期策略（被访问过后的过期时间怎么对待问题）
public enum ExpirationExtending {
    
    case none // 什么也不做，还是按照原来的过期时间算
    
    case cacheTime // 根据原来的缓存时间来处理延期
    
    case expirationTime(_ expiration: StorageExpiration) // 根据新提供的缓存过期策略来处理延期
}

// 代表可以计算内存开销的类型，获取内存占用的方法
public protocol CacheCostCalculable {
    var cacheCost: Int { get }
}

// 代表可以转为Data，也可以从Data转回来的类型
public protocol DataTransformable {
    func toData() throws -> Data
    static func fromData(_ data: Data) throws -> Self
    static var empty: Self { get }
}
