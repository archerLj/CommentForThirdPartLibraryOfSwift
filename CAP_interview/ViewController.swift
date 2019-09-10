//
//  ViewController.swift
//  CAP_interview
//
//  Created by ArcherLj on 2019/9/10.
//  Copyright © 2019 ArcherLj. All rights reserved.
//

import UIKit
import Kingfisher
import SnapKit

class ViewController: UIViewController {

    lazy var imageView = UIImageView()
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(imageView)
        imageView.snp.makeConstraints { (make) in
            make.size.equalTo(CGSize(width: 300, height: 300))
            make.center.equalToSuperview()
        }
        
        let url = URL(string: "http://f.hiphotos.baidu.com/image/pic/item/b151f8198618367aa7f3cc7424738bd4b31ce525.jpg")!
        imageView.kf.setImage(with: .network(url),
                              placeholder: nil,
                              options: [.transition(.fade(1))],
                              progressBlock: { (received, total) in
                                print("\(received), \(total)")
        }, completionHandler: { result in
            switch result {
            case .success(let value):
                print("Task done for: \(value.source.url?.absoluteString ?? "")")
            case .failure(let error):
                print("Job failed: \(error.localizedDescription)")
            }
        })
    }


    // 一个宽高为100，居于父视图中心
    func demo1() {
        
        let testView = UIView()
        testView.backgroundColor = UIColor.cyan
        view.addSubview(testView)
        
        testView.snp.makeConstraints { (make) in
//            make.width.equalTo(100)
//            make.height.equalTo(100)
            make.width.height.equalTo(100)
            make.center.equalToSuperview()
        }
    }
    
    
    // view2位于view1内，view2位于view1的中心，并且距离view的边距的距离都是20
    func demo2() {
        
        // 黑色试图作为父视图
        let view1 = UIView()
        view1.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view1.center = view.center
        view1.backgroundColor = UIColor.black
        view.addSubview(view1)
        
        // 测试视图
        let view2 = UIView()
        view2.backgroundColor = UIColor.magenta
        view1.addSubview(view2)
        view2.snp.makeConstraints { (make) in
            // 1
//            make.left.top.equalTo(20)
//            make.right.bottom.equalTo(-20)
            
            // 2
//            make.left.equalToSuperview().offset(20)
//            make.top.equalToSuperview().offset(20)
//            make.bottom.equalToSuperview().offset(-20)
//            make.right.equalToSuperview().offset(-20)
            
            // 3
            make.edges.equalTo(UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
        }
    }
    
    // 让view2的水平中心线小于等于view1的左边
    func demo3() {
        
        let view1 = UIView()
        view1.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view1.center = view.center
        view1.backgroundColor = UIColor.black
        view.addSubview(view1)
        
        let view2 = UIView()
        view2.backgroundColor = UIColor.magenta
        view1.addSubview(view2)
        view2.snp.makeConstraints { (make) in
            make.width.height.equalTo(100)
            make.top.equalTo(view1.snp.bottom).offset(10)
            make.centerX.lessThanOrEqualTo(view1.snp.left)
        }
    }
    
    // 让view2的左边 >= 父试图的左边，greaterThanOrEqualTo
    func demo4() {
        
        //
        let view1 = UIView()
        view1.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view1.center = view.center
        view1.backgroundColor = UIColor.black
        view.addSubview(view1)
        
        //
        let view2 = UIView()
        view2.backgroundColor = UIColor.magenta
        view1.addSubview(view2)
        view2.snp.makeConstraints { (make) in
            make.top.equalTo(view1.snp.bottom).offset(10)
//            make.width.height.equalTo(100) // 和下面效果一样
            make.size.equalTo(CGSize(width: 100, height: 100))
            make.left.greaterThanOrEqualTo(view1)
//            make.left.equalToSuperview() // 这里greaterThanEqualTo完全可以替换为equalToSuperview
        }
    }
    
    // greaterThanOrEqualTo 和 lessThanOrEqualTo同时存在时，以greaterThanOrEqualTo为主
    func demo5() {
        //
        let view1 = UIView()
        view1.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view1.center = view.center
        view1.backgroundColor = UIColor.black
        view.addSubview(view1)
        
        //
        let view2 = UIView()
        view2.backgroundColor = UIColor.magenta
        view1.addSubview(view2)
        view2.snp.makeConstraints { (make) in
            make.width.lessThanOrEqualTo(300)
            make.width.greaterThanOrEqualTo(200)
            make.height.equalTo(100)
            make.center.equalToSuperview()
        }
    }
    
    func demo6() {
        //
        let view1 = UIView()
        view1.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view1.center = view.center
        view1.backgroundColor = UIColor.black
        view.addSubview(view1)
        
        //
        let view2 = UIView()
        view2.backgroundColor = UIColor.magenta
        view1.addSubview(view2)
        view2.snp.makeConstraints { (make) in
            make.left.lessThanOrEqualTo(20)
            make.right.equalTo(-40)
            make.height.equalTo(100)
            make.center.equalToSuperview()
        }
    }
    
    // 设置优先级，优先级不能超过1000，否则崩溃
    func demo7() {
        //
        let view1 = UIView()
        view1.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view1.center = view.center
        view1.backgroundColor = UIColor.black
        view.addSubview(view1)
        
        //
        let view2 = UIView()
        view2.backgroundColor = UIColor.magenta
        view1.addSubview(view2)
        view2.snp.makeConstraints { (make) in
            make.width.equalTo(100).priority(666)
            make.width.equalTo(250).priority(999) // 这里250的优先级999比100优先级666大，所以以250为准
            make.height.equalTo(111)
            make.center.equalToSuperview()
        }
    }
    
    
    // 更新约束
    var updateConstraint: Constraint?
    func demo8() {
        // 黑色视图作为父视图
        let view1 = UIView()
        view1.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        view1.center = view.center
        view1.backgroundColor = UIColor.black
        view.addSubview(view1)
        
        // 测试视图
        let view2 = UIView()
        view2.backgroundColor = UIColor.magenta
        view1.addSubview(view2)
        view2.snp.makeConstraints { (make) in
            make.width.height.equalTo(100)
            self.updateConstraint = make.top.left.equalTo(10).constraint
        }
        
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor.brown
        button.frame = CGRect(x: 100, y: 80, width: 50, height: 30)
        button.setTitle("更新", for: .normal)
        button.addTarget(self, action: #selector(constraintUpdate), for: .touchUpInside)
        view.addSubview(button)
    }
    
    @objc func constraintUpdate() {
        self.updateConstraint?.update(offset: 50) // 更新为距离父视图左，上为50
    }
    
    
    // snp更新约束
    let blackView = UIView()
    func demo9() {
        blackView.backgroundColor = UIColor.black
        view.addSubview(blackView)
        blackView.snp.makeConstraints { (make) in
            
            // 四个约束确定位置和大小
            make.width.equalTo(100)
            make.height.equalTo(150)
            make.top.equalTo(10)
            make.centerX.equalToSuperview()
        }
        
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor.brown
        button.frame = CGRect(x: 100, y: 80, width: 50, height: 30)
        button.setTitle("更新", for: .normal)
        button.addTarget(self, action: #selector(constraintUpdate2), for: .touchUpInside)
        view.addSubview(button)
    }
    
    @objc func constraintUpdate2() {
        blackView.snp.updateConstraints { (make) in
            make.top.equalTo(300)
        }
        
        
        // 注意
        // makeConstriants是增加约束，可能会导致存在多个同样的约束，导致约束冲突
        // 如果只是更新约束，就用updateConstriants
        // 如果要删除所有约束，重新添加约束，就用下面的remakeConstraints
        blackView.snp.makeConstraints { (make) in
            make.top.equalToSuperview()
        }
        
        // 删除所有约束，重新添加
        blackView.snp.remakeConstraints { (make) in
            
        }
    }
    
//    override func updateViewConstraints() {
//
//        // 也可以将snp.updateConstraints写在这里
//
//        super.updateViewConstraints()
//    }
}

