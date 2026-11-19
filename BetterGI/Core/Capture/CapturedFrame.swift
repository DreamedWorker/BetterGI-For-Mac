//
//  CapturedFrame.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/20.
//

import Foundation
import CoreMedia
import CoreVideo

/// 采集队列交给处理队列的一帧画面
struct CapturedFrame {
    /// 原始像素缓冲区，格式为 BGRA
    let pixelBuffer: CVPixelBuffer
    
    /// 视频帧时间戳
    let presentationTimeStamp: CMTime
    
    /// 图像宽度（像素）
    var width: Int {
        CVPixelBufferGetWidth(pixelBuffer)
    }
    
    /// 图像高度（像素）
    var height: Int {
        CVPixelBufferGetHeight(pixelBuffer)
    }
}
