//
//  Placeholder.swift
//  Kingfisher
//
//  Created by Tieme van Veen on 28/08/2017.
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

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/**
 该类型在加载图片，或者获取图片失败的时候设置占位用
 从后面的代码来看，这里既可以用Image也可以用UIView作为占位
 */
public protocol Placeholder {
    
    // 将placeholder设置到imageview的方法
    func add(to imageView: ImageView)
    
    // 从imageview移除placeholder的方法
    func remove(from imageView: ImageView)
}

// 让Image遵守 palceholder协议，直接将图片设置给imageview的image
extension Image: Placeholder {
    
    public func add(to imageView: ImageView) { imageView.image = self }

    public func remove(from imageView: ImageView) { imageView.image = nil }
}

// 当遵守占位图片协议的是一个UIView的时候
extension Placeholder where Self: View {
    
    // 直接将UIView作为子视图设置给imageView即可
    public func add(to imageView: ImageView) {
        imageView.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false //使用自动布局

        // 新添加的自动布局isActivie默认是false，只有是true的时候才会触发布局计算
        centerXAnchor.constraint(equalTo: imageView.centerXAnchor).isActive = true
        centerYAnchor.constraint(equalTo: imageView.centerYAnchor).isActive = true
        heightAnchor.constraint(equalTo: imageView.heightAnchor).isActive = true
        widthAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true
    }

    // 直接移除占位View
    public func remove(from imageView: ImageView) {
        removeFromSuperview()
    }
}
