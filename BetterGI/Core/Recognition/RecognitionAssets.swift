//
//  RecognitionAssets.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import Foundation
import opencv2

nonisolated enum RecognitionAssetError: LocalizedError {
    case missingFile(String)
    case invalidConfiguration(String, reason: String)
    case missingObject(String, feature: String)
    case missingRegion(String, feature: String)
    case unreadableTemplate(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return "缺少资源文件 \(path)"
        case .invalidConfiguration(let path, let reason):
            return "\(path) 格式有误：\(reason)"
        case .missingObject(let name, let feature):
            return "\(RecognitionAssets.rootDirectory)/\(feature)/Recognition.json 中没有识别对象「\(name)」"
        case .missingRegion(let name, let feature):
            return "\(RecognitionAssets.rootDirectory)/\(feature)/Recognition.json 中的「\(name)」缺少 roi"
        case .unreadableTemplate(let path):
            return "无法读取模板图 \(path)"
        }
    }
}

/// Recognition.json 中的一个模板匹配对象。
nonisolated struct TemplateAsset: @unchecked Sendable {
    let name: String
    /// 1080p 下的灰度模板（CV_8UC1）
    let template: Mat
    /// 搜索区域；为空时由调用方按上下文决定（例如设置图标跟随拾取键的位置）
    let region: RegionExpression?
    /// 该模板对应的完整识别对象配置（阈值、匹配算法、参考画布等）。
    let object: RecognitionObject

    var width: Int { Int(template.cols()) }
    var height: Int { Int(template.rows()) }
}

nonisolated enum RecognitionAssets {
    /// App 资源目录下存放识别资源的文件夹
    static let rootDirectory = "Resources"

    /// 只解析 `feature` 下的 Recognition.json，不加载模板图。
    static func loadConfiguration(
        feature: String,
        bundle: Bundle = .main
    ) throws -> RecognitionConfiguration {
        let featureDirectory = "\(rootDirectory)/\(feature)"
        let configPath = "\(featureDirectory)/Recognition.json"

        guard let configURL = resourceURL(
            in: bundle,
            fileName: "Recognition.json",
            subdirectory: featureDirectory
        ) else {
            throw RecognitionAssetError.missingFile(configPath)
        }

        do {
            return try RecognitionConfiguration.parse(data: Data(contentsOf: configURL), source: configPath)
        } catch {
            throw RecognitionAssetError.invalidConfiguration(configPath, reason: error.localizedDescription)
        }
    }

    /// 加载 `feature` 下所有模板匹配对象。
    static func load(feature: String, bundle: Bundle = .main) throws -> [String: TemplateAsset] {
        let featureDirectory = "\(rootDirectory)/\(feature)"
        let templateDirectory = "\(featureDirectory)/1920x1080"
        let configPath = "\(featureDirectory)/Recognition.json"

        let configuration = try loadConfiguration(feature: feature, bundle: bundle)

        var assets: [String: TemplateAsset] = [:]
        for (name, object) in configuration.objects where object.type == .templateMatch {
            guard let fileName = object.template else {
                throw RecognitionAssetError.invalidConfiguration(
                    configPath,
                    reason: "识别对象「\(name)」缺少 template"
                )
            }

            let location = templateLocation(fileName, baseDirectory: templateDirectory)
            let templatePath = "\(location.subdirectory)/\(location.fileName)"
            guard let url = resourceURL(
                in: bundle,
                fileName: location.fileName,
                subdirectory: location.subdirectory
            ) else {
                throw RecognitionAssetError.missingFile(templatePath)
            }

            assets[name] = TemplateAsset(
                name: name,
                template: try loadGrayTemplate(at: url, displayPath: templatePath),
                region: object.roi,
                object: object
            )
        }
        return assets
    }

    /// 模板名支持 `子目录/文件名`，可以使用相对路径。
    private static func templateLocation(
        _ fileName: String,
        baseDirectory: String
    ) -> (subdirectory: String, fileName: String) {
        let normalized = fileName.replacingOccurrences(of: "\\", with: "/")
        let directory = (normalized as NSString).deletingLastPathComponent
        guard !directory.isEmpty, directory != ".", directory != "/" else {
            return (baseDirectory, normalized)
        }
        return ("\(baseDirectory)/\(directory)", (normalized as NSString).lastPathComponent)
    }

    /// 按彩色读入后再转灰度，与采集画面的灰度转换方式一致；透明通道直接丢弃。
    private static func loadGrayTemplate(at url: URL, displayPath: String) throws -> Mat {
        let color = Imgcodecs.imread(filename: url.path, flags: ImreadModes.IMREAD_COLOR.rawValue)
        guard !color.empty() else {
            throw RecognitionAssetError.unreadableTemplate(displayPath)
        }

        let gray = Mat()
        Imgproc.cvtColor(src: color, dst: gray, code: .COLOR_BGR2GRAY)
        return gray
    }

    /// 只在指定目录查找，不退回资源根目录。
    private static func resourceURL(in bundle: Bundle, fileName: String, subdirectory: String) -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
    }
}
