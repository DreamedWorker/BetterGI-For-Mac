//
//  BGRAFrame.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import CoreGraphics
import CoreVideo
import Foundation
import opencv2

nonisolated enum BGRAFrameError: LocalizedError {
    case unsupportedPixelFormat(OSType)
    case baseAddressUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedPixelFormat(let format):
            return "不支持的像素格式：\(format)"
        case .baseAddressUnavailable:
            return "无法读取像素缓冲区"
        }
    }
}

/// 已锁定的 BGRA 像素缓冲区的只读视图。
///
/// 只能在 `withLocked(_:_:)` 的闭包内使用：闭包返回后缓冲区解锁，内部指针随即失效。
/// 需要保留的数据（例如 `grayMat(in:)` 的结果）都是复制出来的新内存。
nonisolated struct BGRAFrame {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let base: UnsafeRawPointer

    static func withLocked<T>(
        _ pixelBuffer: CVPixelBuffer,
        _ body: (BGRAFrame) throws -> T
    ) throws -> T {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            throw BGRAFrameError.unsupportedPixelFormat(format)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw BGRAFrameError.baseAddressUnavailable
        }

        let frame = BGRAFrame(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            base: UnsafeRawPointer(base)
        )
        return try body(frame)
    }

    /// 指定像素的近似亮度（0...255），即 0.299R + 0.587G + 0.114B 的整数近似。
    @inline(__always)
    func luminance(x: Int, y: Int) -> Int {
        let pixel = base
            .advanced(by: y * bytesPerRow + x * 4)
            .assumingMemoryBound(to: UInt8.self)
        // 内存顺序为 B, G, R, A
        return (Int(pixel[2]) * 77 + Int(pixel[1]) * 150 + Int(pixel[0]) * 29) >> 8
    }

    /// 把指定区域复制出来并转换成灰度图（CV_8UC1）。
    func grayMat(in rect: PixelRect) -> Mat {
        let bgra = Mat(rows: Int32(rect.height), cols: Int32(rect.width), type: CvType.CV_8UC4)
        let destination = UnsafeMutableRawPointer(bgra.dataPointer())
        // CV_8UC4 每个通道 1 字节，step1 即每行字节数
        let destinationStride = bgra.step1()
        let rowBytes = rect.width * 4

        for row in 0..<rect.height {
            let source = base.advanced(by: (rect.y + row) * bytesPerRow + rect.x * 4)
            destination
                .advanced(by: row * destinationStride)
                .copyMemory(from: source, byteCount: rowBytes)
        }

        let gray = Mat()
        Imgproc.cvtColor(src: bgra, dst: gray, code: .COLOR_BGRA2GRAY)
        return gray
    }
}

/// 整数像素矩形，原点在左上角。
nonisolated struct PixelRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// 把 `rect` 向外取整并裁剪到 `width × height` 的画面内；裁剪后为空时返回 `nil`。
    init?(_ rect: CGRect, within width: Int, _ height: Int) {
        guard !rect.isNull, !rect.isInfinite else { return nil }

        let minX = max(0, Int(rect.minX.rounded(.down)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        guard maxX > minX, maxY > minY else { return nil }

        self.x = minX
        self.y = minY
        self.width = maxX - minX
        self.height = maxY - minY
    }
}
