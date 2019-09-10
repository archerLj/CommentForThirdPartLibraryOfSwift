//
//  Source.swift
//  Kingfisher
//
//  Created by onevcat on 2018/11/17.
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

/// Represents an image setting source for Kingfisher methods.
///
/// A `Source` value indicates the way how the target image can be retrieved and cached.
///
/// - network: The target image should be got from network remotely. The associated `Resource`
///            value defines detail information like image URL and cache key.
/// - provider: The target image should be provided in a data format. Normally, it can be an image
///             from local storage or in any other encoding format (like Base64).
public enum Source {

    /// Represents the source task identifier when setting an image to a view with extension methods.
    public enum Identifier {

        /// The underlying value type of source identifier.
        public typealias Value = UInt
        static var current: Value = 0
        static func next() -> Value {
            current += 1
            return current
        }
    }

    // MARK: Member Cases
    
    /**
     表示目标图片应该从网络上获取
     Resource是一个协议，协议中包括缓存用的key和目标图片的url。
     URL扩展直接遵循了Resource类，所以可以直接传一个url对象给network
     */
    case network(Resource)
    
    /**
     表示目标图片是从本地存储或者其他编码格式的数据获取,比如Base64
     ImageDataProvider协议包括了缓存用的key以及从获取图片Data的方法
     */
    case provider(ImageDataProvider)

    // MARK: Getting Properties

    // 缓存用的key
    public var cacheKey: String {
        switch self {
        case .network(let resource): return resource.cacheKey
        case .provider(let provider): return provider.cacheKey
        }
    }

    // 获取url，如果是network类型，则获取resource对象的downloadURL，本地数据返回nil
    public var url: URL? {
        switch self {
        case .network(let resource): return resource.downloadURL
        // `ImageDataProvider` does not provide a URL. All it cares is how to get the data back.
        case .provider(_): return nil
        }
    }
}

extension Source {
    
    // 判断是否是.network类型
    var asResource: Resource? {
        guard case .network(let resource) = self else {
            return nil
        }
        return resource
    }

    // 判断是否是.provider类型
    var asProvider: ImageDataProvider? {
        guard case .provider(let provider) = self else {
            return nil
        }
        return provider
    }
}
