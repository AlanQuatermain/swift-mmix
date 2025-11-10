//
//  Extensions.swift
//  swift-mmix
//
//  Created by Jim Dovey on 11/8/25.
//

extension BinaryInteger {
    var isPowerOf2: Bool {
        self > 0 && (self & (self - 1)) == 0
    }
}
